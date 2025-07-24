import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader
import clip
from PIL import Image
import os
import json
from tqdm import tqdm
import numpy as np
import math
from tourist_photo_augmentation import TouristPhotoAugmentation, TextAugmentation, AugmentationPresets

class LoRALayer(nn.Module):
    def __init__(self, in_features, out_features, rank=16, alpha=32):
        super().__init__()
        self.rank = rank
        self.alpha = alpha
        self.scaling = alpha / rank
        
        # LoRA 파라미터 초기화
        self.lora_A = nn.Parameter(torch.randn(rank, in_features) * 0.01)
        self.lora_B = nn.Parameter(torch.zeros(out_features, rank))
        
    def forward(self, x):
        # LoRA: x + (x @ A^T @ B^T) * scaling
        lora_output = (x @ self.lora_A.T @ self.lora_B.T) * self.scaling
        return lora_output

class LoRACLIP(nn.Module):
    def __init__(self, clip_model, rank=16, alpha=32):
        super().__init__()
        self.clip_model = clip_model
        self.rank = rank
        self.alpha = alpha
        
        # 원본 모델 파라미터 고정
        for param in self.clip_model.parameters():
            param.requires_grad = False
        
        # LoRA 레이어 추가
        self.lora_layers = nn.ModuleDict()
        self.add_lora_layers()
        
        print(f"[SUCCESS] LoRA layers added with rank={rank}, alpha={alpha}")
        print(f"[INFO] Trainable parameters: {sum(p.numel() for p in self.parameters() if p.requires_grad):,}")
        print(f"[INFO] Total parameters: {sum(p.numel() for p in self.parameters()):,}")
    
    def add_lora_layers(self):
        """주요 어텐션 레이어에 LoRA 추가"""
        # Vision Transformer의 어텐션 레이어들
        for i in range(12):  # ViT-B/32는 12개 레이어
            # Self-attention의 query, key, value 프로젝션
            for proj_name in ['q_proj', 'k_proj', 'v_proj', 'out_proj']:
                layer_name = f'visual_transformer_layer_{i}_{proj_name}'
                self.lora_layers[layer_name] = LoRALayer(768, 768, self.rank, self.alpha)
        
        # Text Transformer의 어텐션 레이어들  
        for i in range(12):  # Text encoder도 12개 레이어
            for proj_name in ['q_proj', 'k_proj', 'v_proj', 'out_proj']:
                layer_name = f'text_transformer_layer_{i}_{proj_name}'
                self.lora_layers[layer_name] = LoRALayer(512, 512, self.rank, self.alpha)
    
    def forward(self, image, text):
        # 이미지 인코딩 (LoRA 적용)
        image_features = self.encode_image_with_lora(image)
        
        # 텍스트 인코딩 (LoRA 적용)
        text_features = self.encode_text_with_lora(text)
        
        # 정규화
        image_features = image_features / image_features.norm(dim=-1, keepdim=True)
        text_features = text_features / text_features.norm(dim=-1, keepdim=True)
        
        # 로짓 계산
        logit_scale = self.clip_model.logit_scale.exp()
        logits_per_image = logit_scale * image_features @ text_features.t()
        logits_per_text = logits_per_image.t()
        
        return logits_per_image, logits_per_text
    
    def encode_image_with_lora(self, image):
        """이미지 인코딩 + LoRA"""
        x = self.clip_model.visual.conv1(image)
        x = x.reshape(x.shape[0], x.shape[1], -1)
        x = x.permute(0, 2, 1)
        x = torch.cat([self.clip_model.visual.class_embedding.to(x.dtype) + torch.zeros(x.shape[0], 1, x.shape[-1], dtype=x.dtype, device=x.device), x], dim=1)
        x = x + self.clip_model.visual.positional_embedding.to(x.dtype)
        x = self.clip_model.visual.ln_pre(x)
        
        x = x.permute(1, 0, 2)
        
        # Transformer 블록들 (LoRA 적용)
        for i, block in enumerate(self.clip_model.visual.transformer.resblocks):
            # 원본 블록 통과
            residual = x
            x = block.ln_1(x)
            
            # Multi-head attention with LoRA
            x_attn, _ = block.attn(x, x, x)
            
            # LoRA 추가
            batch_size, seq_len, embed_dim = x.shape
            x_flat = x.view(-1, embed_dim)
            
            # 각 프로젝션에 LoRA 적용
            for proj_name in ['q_proj', 'k_proj', 'v_proj']:
                layer_name = f'visual_transformer_layer_{i}_{proj_name}'
                if layer_name in self.lora_layers:
                    lora_output = self.lora_layers[layer_name](x_flat)
                    x_attn += lora_output.view(batch_size, seq_len, embed_dim)
            
            x = residual + x_attn
            
            # MLP
            residual = x
            x = block.ln_2(x)
            x = block.mlp(x)
            x = residual + x
        
        x = x.permute(1, 0, 2)
        x = self.clip_model.visual.ln_post(x[:, 0, :])
        
        if self.clip_model.visual.proj is not None:
            x = x @ self.clip_model.visual.proj
        
        return x
    
    def encode_text_with_lora(self, text):
        """텍스트 인코딩 + LoRA (간단화)"""
        # 복잡성을 줄이기 위해 원본 텍스트 인코더 사용
        # 실제로는 텍스트 트랜스포머에도 LoRA를 적용할 수 있음
        return self.clip_model.encode_text(text)

class SeoulTouristDataset(Dataset):
    def __init__(self, data_path, transform=None, augment=True, is_validation=False):
        self.data_path = data_path
        self.transform = transform
        self.augment = augment
        self.is_validation = is_validation
        
        # 증강기 초기화
        if self.augment and not self.is_validation:
            self.image_augmenter = AugmentationPresets.moderate_augmentation()  # 중간 강도의 증강 사용
            self.text_augmenter = TextAugmentation()
        
        # 장소 매핑
        self.place_mapping = {
            '경복궁': 'Gyeongbokgung Palace',
            '경희궁': 'Gyeonghui Palace', 
            '광화문': 'Gwanghwamun Gate',
            '남산서울타워': 'Namsan Seoul Tower',
            '북촌한옥마을': 'Bukchon Hanok Village',
            '청계천': 'Cheonggyecheon Stream',
            '독립문': 'Independence Gate',
            '서울도서관': 'Seoul Metropolitan Library'
        }
        
        self.samples = self.load_samples()
        self.print_dataset_info()
    
    def load_samples(self):
        samples = []
        for korean_name, english_name in self.place_mapping.items():
            place_dir = os.path.join(self.data_path, korean_name)
            if not os.path.exists(place_dir):
                continue
                
            for filename in os.listdir(place_dir):
                if not filename.lower().endswith(('.jpg', '.jpeg', '.png')):
                    continue
                    
                img_path = os.path.join(place_dir, filename)
                
                # 기본 샘플 추가
                samples.append((img_path, english_name))
                
                # 검증 데이터가 아니고 증강이 활성화된 경우에만 텍스트 증강 추가
                if self.augment and not self.is_validation:
                    text_variations = self.text_augmenter.get_variations(english_name, korean_name)
                    for text in text_variations[:2]:  # 각 이미지당 2개의 텍스트 변형만 사용
                        samples.append((img_path, text))
        
        return samples
    
    def print_dataset_info(self):
        """데이터셋 정보 출력"""
        print(f"\n[INFO] Dataset loaded: {len(self.samples)} samples")
        
        # 각 장소별 이미지 수 계산
        place_counts = {}
        for img_path, _ in self.samples:
            for place in self.place_mapping.keys():
                if place in img_path:
                    place_counts[place] = place_counts.get(place, 0) + 1
        
        for place, count in place_counts.items():
            print(f"  - {place}: {count}장")
        
        if self.augment and not self.is_validation:
            print("\n[INFO] Augmentation enabled:")
            print("  - Image: Moderate augmentation (60% probability)")
            print("  - Text: 2 variations per image")
    
    def __len__(self):
        return len(self.samples)
    
    def __getitem__(self, idx):
        img_path, text = self.samples[idx]
        
        try:
            # 이미지 로드
            image = Image.open(img_path).convert('RGB')
            
            # 증강이 활성화되고 검증 데이터가 아닌 경우 이미지 증강 적용
            if self.augment and not self.is_validation:
                image = self.image_augmenter(image)
            
            # CLIP 전처리 적용
            if self.transform:
                image = self.transform(image)
            
            return image, text
            
        except Exception as e:
            print(f"Error loading {img_path}: {e}")
            return self.__getitem__(0)

class CLIPLoRATrainer:
    def __init__(self, rank=16, alpha=32, learning_rate=1e-4, batch_size=8):
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        self.batch_size = batch_size
        self.learning_rate = learning_rate
        
        print(f"[INFO] Initializing CLIP-LoRA Trainer")
        print(f"[INFO] Device: {self.device}")
        
        # CLIP 모델 로드 시 float32로 변환
        clip_model, self.preprocess = clip.load("ViT-B/32", device=self.device)
        clip_model = clip_model.float()  # float32로 변환
        
        # LoRA 모델 생성
        self.model = LoRACLIP(clip_model, rank=rank, alpha=alpha).to(self.device)
        
        # 모든 파라미터를 float32로 변환
        for param in self.model.parameters():
            param.data = param.data.float()
        
        # 옵티마이저 (LoRA 파라미터만)
        self.optimizer = optim.AdamW(
            [p for p in self.model.parameters() if p.requires_grad],
            lr=learning_rate,
            weight_decay=0.01
        )
        
        # 스케줄러
        self.scheduler = optim.lr_scheduler.CosineAnnealingLR(
            self.optimizer, T_max=50, eta_min=1e-6
        )
        
        print("[SUCCESS] CLIP-LoRA Trainer initialized!")
    
    def load_existing_model(self, model_path):
        """기존 학습된 LoRA 모델 로드"""
        try:
            if not os.path.exists(model_path):
                print(f"[ERROR] 모델 파일을 찾을 수 없습니다: {model_path}")
                return False
            
            print(f"[INFO] 기존 모델 로드 중: {model_path}")
            checkpoint = torch.load(model_path, map_location=self.device)
            
            # LoRA 파라미터 로드
            if 'lora_state_dict' in checkpoint:
                # LoRA 파라미터만 있는 경우
                lora_state_dict = checkpoint['lora_state_dict']
                
                # 현재 모델의 LoRA 파라미터와 매칭되는 것만 로드
                current_state = self.model.state_dict()
                loaded_params = 0
                
                for name, param in lora_state_dict.items():
                    if name in current_state and current_state[name].shape == param.shape:
                        current_state[name].copy_(param)
                        loaded_params += 1
                
                print(f"[SUCCESS] LoRA 파라미터 로드 완료: {loaded_params}개")
                
                # 옵티마이저 상태도 로드 (있는 경우)
                if 'optimizer_state_dict' in checkpoint:
                    try:
                        self.optimizer.load_state_dict(checkpoint['optimizer_state_dict'])
                        print("[SUCCESS] 옵티마이저 상태 로드 완료")
                    except:
                        print("[WARNING] 옵티마이저 상태 로드 실패 - 새로 시작합니다")
                        
            elif 'model_state_dict' in checkpoint:
                # 전체 모델 상태가 있는 경우
                model_state = checkpoint['model_state_dict']
                
                # LoRA 파라미터만 추출해서 로드
                current_state = self.model.state_dict()
                loaded_params = 0
                
                for name, param in model_state.items():
                    if name in current_state and 'lora' in name and current_state[name].shape == param.shape:
                        current_state[name].copy_(param)
                        loaded_params += 1
                
                print(f"[SUCCESS] 모델에서 LoRA 파라미터 추출 및 로드 완료: {loaded_params}개")
            
            else:
                print("[ERROR] 호환되지 않는 모델 형식입니다")
                return False
            
            return True
            
        except Exception as e:
            print(f"[ERROR] 모델 로드 실패: {e}")
            return False
    
    def contrastive_loss(self, logits_per_image, logits_per_text):
        """대조 학습 손실"""
        batch_size = logits_per_image.shape[0]
        labels = torch.arange(batch_size, device=self.device)
        
        loss_img = nn.CrossEntropyLoss()(logits_per_image, labels)
        loss_txt = nn.CrossEntropyLoss()(logits_per_text, labels)
        
        return (loss_img + loss_txt) / 2
    
    def train_epoch(self, dataloader):
        """한 에포크 훈련"""
        self.model.train()
        total_loss = 0
        num_batches = 0
        
        progress_bar = tqdm(dataloader, desc="Training")
        
        for batch_idx, (images, texts) in enumerate(progress_bar):
            try:
                images = images.float().to(self.device)  # float32로 명시
                texts = clip.tokenize(texts, truncate=True).to(self.device)
                
                self.optimizer.zero_grad()
                
                # Forward pass
                logits_per_image, logits_per_text = self.model(images, texts)
                
                # 손실 계산
                loss = self.contrastive_loss(logits_per_image, logits_per_text)
                
                # 역전파
                loss.backward()
                
                # 그래디언트 클리핑
                torch.nn.utils.clip_grad_norm_(
                    [p for p in self.model.parameters() if p.requires_grad], 
                    max_norm=1.0
                )
                
                self.optimizer.step()
                
                total_loss += loss.item()
                num_batches += 1
                
                progress_bar.set_postfix({
                    'Loss': f'{loss.item():.4f}',
                    'Avg Loss': f'{total_loss/num_batches:.4f}'
                })
                
            except Exception as e:
                print(f"Error in batch {batch_idx}: {e}")
                continue
        
        return total_loss / max(num_batches, 1)
    
    def validate(self, val_loader):
        """검증"""
        self.model.eval()
        total_loss = 0
        num_batches = 0
        
        with torch.no_grad():
            for images, texts in tqdm(val_loader, desc="Validating"):
                try:
                    images = images.float().to(self.device)  # float32로 명시
                    texts = clip.tokenize(texts, truncate=True).to(self.device)
                    
                    logits_per_image, logits_per_text = self.model(images, texts)
                    loss = self.contrastive_loss(logits_per_image, logits_per_text)
                    
                    total_loss += loss.item()
                    num_batches += 1
                    
                except Exception as e:
                    print(f"Error in validation batch: {e}")
                    continue
        
        return total_loss / max(num_batches, 1)
    
    def train(self, train_dataset, val_dataset=None, num_epochs=20):
        """LoRA 훈련 실행"""
        print("="*60)
        print("[START] CLIP-LoRA Fine-tuning for Seoul Tourist Spots")
        print("="*60)
        
        train_loader = DataLoader(
            train_dataset, 
            batch_size=self.batch_size, 
            shuffle=True,
            num_workers=0,  # worker 수 감소
            pin_memory=True
        )
        
        val_loader = None
        if val_dataset:
            val_loader = DataLoader(
                val_dataset, 
                batch_size=self.batch_size, 
                shuffle=False,
                num_workers=0,  # worker 수 감소
                pin_memory=True
            )
        
        best_val_loss = float('inf')
        train_losses = []
        val_losses = []
        
        for epoch in range(num_epochs):
            print(f"\n{'='*20} Epoch {epoch+1}/{num_epochs} {'='*20}")
            
            # 훈련
            train_loss = self.train_epoch(train_loader)
            train_losses.append(train_loss)
            print(f"[INFO] Train Loss: {train_loss:.4f}")
            
            # 검증
            if val_loader:
                val_loss = self.validate(val_loader)
                val_losses.append(val_loss)
                print(f"[INFO] Val Loss: {val_loss:.4f}")
                
                # 최고 모델 저장
                if val_loss < best_val_loss:
                    best_val_loss = val_loss
                    self.save_model(f"best_clip_lora_epoch_{epoch+1}.pth")
                    print(f"[SUCCESS] New best model saved!")
            
            self.scheduler.step()
            print(f"[INFO] Learning Rate: {self.scheduler.get_last_lr()[0]:.2e}")
        
        print("\n[SUCCESS] LoRA Fine-tuning completed!")
        return train_losses, val_losses
    
    def save_model(self, filename):
        """LoRA 모델 저장"""
        save_path = filename  # 전달받은 경로를 그대로 사용
        
        # LoRA 파라미터만 저장
        lora_state_dict = {
            name: param for name, param in self.model.named_parameters() 
            if param.requires_grad
        }
        
        torch.save({
            'lora_state_dict': lora_state_dict,
            'rank': self.model.rank,
            'alpha': self.model.alpha,
            'optimizer_state_dict': self.optimizer.state_dict(),
        }, save_path)
        
        print(f"[SUCCESS] LoRA model saved: {save_path}")

def main():
    # 테스트 모드 설정 (환경변수 또는 인자로 제어)
    import sys
    TEST_MODE = '--test' in sys.argv or os.environ.get('CLIP_TEST_MODE', '').lower() == 'true'
    
    # 학습 모드 선택
    print("="*60)
    print("🎯 CLIP-LoRA 학습 모드 선택")
    print("="*60)
    print("1. 처음부터 새로 학습 (기존 모델 무시)")
    print("2. 기존 모델에 이어서 학습 (권장)")
    print("="*60)
    
    while True:
        try:
            choice = input("선택하세요 (1 또는 2): ").strip()
            if choice in ['1', '2']:
                break
            else:
                print("❌ 잘못된 선택입니다. 1 또는 2를 입력하세요.")
        except KeyboardInterrupt:
            print("\n\n❌ 사용자가 취소했습니다.")
            return
        except:
            print("❌ 잘못된 입력입니다. 1 또는 2를 입력하세요.")
    
    CONTINUE_TRAINING = (choice == '2')
    
    if CONTINUE_TRAINING:
        print("\n✅ 기존 모델에 이어서 학습을 시작합니다!")
        print("📝 독립문과 서울도서관 데이터가 추가로 학습됩니다.")
    else:
        print("\n✅ 처음부터 새로 학습을 시작합니다!")
        print("📝 모든 장소 데이터가 처음부터 학습됩니다.")
    
    if TEST_MODE:
        print("테스트 모드로 실행됩니다!")
        print("빠른 테스트를 위해 설정이 조정됩니다.")
        NUM_EPOCHS = 2  # 테스트용: 2 에포크만
        BATCH_SIZE = 4  # 테스트용: 작은 배치 크기
        LEARNING_RATE = 1e-3  # 테스트용: 높은 학습률
        RANK = 8  # 테스트용: 작은 LoRA rank
        ALPHA = 16  # 테스트용: 작은 alpha
        SAVE_PREFIX = "test_"  # 테스트 모델임을 표시
    else:
        print("프로덕션 모드로 실행됩니다!")
        NUM_EPOCHS = 20
        BATCH_SIZE = 8
        LEARNING_RATE = 1e-4
        RANK = 16
        ALPHA = 32
        SAVE_PREFIX = ""
    
    # 데이터셋 준비
    data_path = "database_images"
    
    if not os.path.exists(data_path):
        print(f"[ERROR] 데이터 경로를 찾을 수 없습니다: {data_path}")
        print("[INFO] 먼저 download_success_images.py를 실행하여 학습 데이터를 준비하세요.")
        return
    
    print(f"데이터셋 로딩: {data_path}")
    
    # 트레이너 초기화 (CLIP 모델 로드도 여기서 처리됨)
    trainer = CLIPLoRATrainer(
        rank=RANK, 
        alpha=ALPHA, 
        learning_rate=LEARNING_RATE, 
        batch_size=BATCH_SIZE
    )
    
    # 기존 모델 로드 (선택한 경우)
    if CONTINUE_TRAINING:
        print("\n" + "="*60)
        print("🔄 기존 모델 로드 중...")
        print("="*60)
        
        # 기존 모델 파일 경로들
        model_files = [
            "fine_tuned_model/best_model.pth",
            "fine_tuned_model/final_model.pth",
            "fine_tuned_model/test_final_model.pth"
        ]
        
        model_loaded = False
        for model_file in model_files:
            if os.path.exists(model_file):
                print(f"🔍 모델 파일 발견: {model_file}")
                if trainer.load_existing_model(model_file):
                    print(f"✅ 기존 모델 로드 성공!")
                    model_loaded = True
                    break
                else:
                    print(f"❌ {model_file} 로드 실패")
        
        if not model_loaded:
            print("⚠️  기존 모델을 찾을 수 없습니다.")
            print("🔄 처음부터 새로 학습을 시작합니다.")
        
        print("="*60)
    
    # 트레이너에서 전처리 파이프라인 가져오기
    preprocess = trainer.preprocess
    
    # 데이터셋 생성
    train_dataset = SeoulTouristDataset(
        data_path=data_path, 
        transform=preprocess,
        augment=True,
        is_validation=False
    )
    
    # 검증 데이터셋 (증강 없이)
    val_dataset = SeoulTouristDataset(
        data_path=data_path,
        transform=preprocess, 
        augment=False,
        is_validation=True
    )
    
    if len(train_dataset) == 0:
        print("[ERROR] 학습 데이터가 없습니다!")
        return
    
    print(f"Train samples: {len(train_dataset)}")
    print(f"Validation samples: {len(val_dataset)}")
    
    # 학습 실행
    print(f"\n학습 시작! (에포크: {NUM_EPOCHS}, 배치 크기: {BATCH_SIZE})")
    print(f"🎯 학습 모드: {'기존 모델 이어서 학습' if CONTINUE_TRAINING else '처음부터 새로 학습'}")
    trainer.train(train_dataset, val_dataset, num_epochs=NUM_EPOCHS)
    
    # 모델 저장 파일명 설정
    mode_prefix = "continue_" if CONTINUE_TRAINING else "new_"
    model_filename = f"{SAVE_PREFIX}{mode_prefix}best_model.pth"
    final_filename = f"{SAVE_PREFIX}{mode_prefix}final_model.pth"
    
    trainer.save_model(f"fine_tuned_model/{model_filename}")
    print(f"[SUCCESS] 모델 저장 완료: fine_tuned_model/{model_filename}")
    
    # 최종 모델도 저장
    torch.save({
        'model_state_dict': trainer.model.state_dict(),
        'rank': RANK,
        'alpha': ALPHA,
        'epoch': NUM_EPOCHS,
        'test_mode': TEST_MODE,
        'continue_training': CONTINUE_TRAINING,
        'training_mode': 'continue' if CONTINUE_TRAINING else 'new'
    }, f"fine_tuned_model/{final_filename}")
    
    print(f"[SUCCESS] 최종 모델 저장 완료: fine_tuned_model/{final_filename}")
    
    if TEST_MODE:
        print("\n[INFO] 테스트 완료!")
        print("[INFO] 실제 학습을 위해서는 --test 옵션 없이 실행하세요.")
    else:
        print("\n[SUCCESS] 학습 완료!")
        print(f"[INFO] 학습 모드: {'기존 모델 이어서 학습' if CONTINUE_TRAINING else '처음부터 새로 학습'}")
        print(f"[INFO] 저장된 모델: {model_filename}, {final_filename}")
        print("[INFO] 새로운 모델을 사용하려면 API 서버를 재시작하세요.")

if __name__ == "__main__":
    main() 