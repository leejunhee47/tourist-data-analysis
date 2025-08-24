import random

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter
import torchvision.transforms as transforms

class TouristPhotoAugmentation:
    """관광지 사진 촬영 상황을 시뮬레이션하는 데이터 증강 클래스"""
    
    def __init__(self, probability=0.7):
        self.probability = probability
        
        # 관광지 촬영 상황별 증강 변환
        self.augmentations = [
            self.lighting_variation,      # 조명/시간대 변화
            self.weather_simulation,      # 날씨 효과
            self.tourist_perspective,     # 관광객 촬영 각도
            self.camera_quality,          # 카메라/스마트폰 품질
            self.crowd_simulation,        # 인파/가림 효과
        ]
    
    def lighting_variation(self, image):
        """조명 및 시간대 변화 시뮬레이션"""
        if random.random() > self.probability:
            return image
            
        # 밝기 조정 (아침/점심/저녁/야간)
        brightness_factor = random.uniform(0.6, 1.4)
        enhancer = ImageEnhance.Brightness(image)
        image = enhancer.enhance(brightness_factor)
        
        # 대비 조정 (흐린 날/맑은 날)
        contrast_factor = random.uniform(0.8, 1.3)
        enhancer = ImageEnhance.Contrast(image)
        image = enhancer.enhance(contrast_factor)
        
        # 색상 온도 변화 (그림자/직사광선)
        color_factor = random.uniform(0.9, 1.2)
        enhancer = ImageEnhance.Color(image)
        image = enhancer.enhance(color_factor)
        
        return image
    
    def weather_simulation(self, image):
        """날씨 효과 시뮬레이션"""
        if random.random() > self.probability:
            return image
            
        weather_effects = [
            self._add_haze,        # 안개/연무
            self._add_rain_effect, # 비 효과
            self._add_brightness,  # 강한 햇빛
        ]
        
        effect = random.choice(weather_effects)
        return effect(image)
    
    def _add_haze(self, image):
        """안개/연무 효과"""
        # 약간의 블러와 밝기 증가로 안개 효과
        image = image.filter(ImageFilter.GaussianBlur(radius=0.5))
        enhancer = ImageEnhance.Brightness(image)
        return enhancer.enhance(1.1)
    
    def _add_rain_effect(self, image):
        """비 효과 (약간 어둡고 대비 감소)"""
        enhancer = ImageEnhance.Brightness(image)
        image = enhancer.enhance(0.8)
        enhancer = ImageEnhance.Contrast(image)
        return enhancer.enhance(0.9)
    
    def _add_brightness(self, image):
        """강한 햇빛 효과"""
        enhancer = ImageEnhance.Brightness(image)
        return enhancer.enhance(1.2)
    
    def tourist_perspective(self, image):
        """관광객 촬영 각도 및 구도 변화"""
        if random.random() > self.probability:
            return image
            
        # PIL 이미지를 numpy 배열로 변환
        img_array = np.array(image)
        h, w = img_array.shape[:2]
        
        # 약간의 회전과 크롭 (핸드헬드 촬영)
        transform = transforms.Compose([
            transforms.ToPILImage(),
            transforms.RandomRotation(degrees=(-5, 5)),
            transforms.RandomResizedCrop(size=(min(h, w), min(h, w)), scale=(0.85, 1.0)),
            transforms.Resize((h, w)),
        ])
        
        try:
            if len(img_array.shape) == 3:
                return transform(img_array)
        except:
            pass
        return image
    
    def camera_quality(self, image):
        """카메라/스마트폰 품질 시뮬레이션"""
        if random.random() > self.probability:
            return image
            
        quality_effects = [
            self._add_noise,       # 노이즈 (저조도)
            self._slight_blur,     # 약간의 흔들림
            self._compression,     # 압축 아티팩트
        ]
        
        effect = random.choice(quality_effects)
        return effect(image)
    
    def _add_noise(self, image):
        """노이즈 추가"""
        img_array = np.array(image)
        noise = np.random.normal(0, 3, img_array.shape).astype(np.uint8)
        noisy = np.clip(img_array.astype(np.int16) + noise, 0, 255).astype(np.uint8)
        return Image.fromarray(noisy)
    
    def _slight_blur(self, image):
        """약간의 블러"""
        return image.filter(ImageFilter.GaussianBlur(radius=0.3))
    
    def _compression(self, image):
        """JPEG 압축 시뮬레이션"""
        # 임시로 JPEG 압축 효과 (품질 저하)
        enhancer = ImageEnhance.Sharpness(image)
        return enhancer.enhance(0.9)
    
    def crowd_simulation(self, image):
        """인파나 장애물로 인한 부분적 가림 효과"""
        if random.random() > self.probability * 0.5:  # 낮은 확률로 적용
            return image
            
        # 이미지 일부를 어둡게 하여 가림 효과 시뮬레이션
        img_array = np.array(image)
        h, w = img_array.shape[:2]
        
        # 랜덤한 위치에 어두운 영역 생성
        if random.random() > 0.5:
            # 하단 가림 (사람 머리 등)
            mask_height = random.randint(h//8, h//4)
            img_array[-mask_height:, :] = img_array[-mask_height:, :] * 0.7
        else:
            # 측면 가림
            mask_width = random.randint(w//10, w//6)
            if random.random() > 0.5:
                img_array[:, :mask_width] = img_array[:, :mask_width] * 0.7
            else:
                img_array[:, -mask_width:] = img_array[:, -mask_width:] * 0.7
        
        return Image.fromarray(img_array.astype(np.uint8))
    
    def __call__(self, image):
        """모든 증강 기법을 랜덤하게 적용"""
        # 원본 이미지 보존을 위해 복사
        augmented_image = image.copy()
        
        # 랜덤하게 1-3개의 증강 기법 적용
        num_augmentations = random.randint(1, 3)
        selected_augmentations = random.sample(self.augmentations, num_augmentations)
        
        for augmentation in selected_augmentations:
            augmented_image = augmentation(augmented_image)
        
        return augmented_image

class TextAugmentation:
    """텍스트 설명 증강 클래스"""
    
    def __init__(self):
        # 기본 텍스트 변형
        self.base_variations = [
            "A photo of {desc}",
            "An image of {desc}",
            "A picture showing {desc}",
            "A view of {desc}",
            "A photograph of {desc}",
            "A daytime photo of {desc}",
            "A tourist photo of {desc}",
            "A scenic view of {desc}",
            "A travel photo showing {desc}",
        ]
        
        # 관광지 유형별 특화 설명
        self.specialized_descriptions = {
            '궁': [
                "A traditional Korean palace architecture photo of {desc}",
                "A historical building photo of {desc}",
                "A royal palace photo of {desc}",
                "A Korean heritage site photo of {desc}",
            ],
            '타워': [
                "A city landmark photo of {desc}",
                "An observation tower photo of {desc}",
                "A Seoul skyline photo featuring {desc}",
                "A communication tower photo of {desc}",
            ],
            '한옥': [
                "A traditional Korean village photo of {desc}",
                "A hanok architecture photo of {desc}",
                "A Korean traditional house photo of {desc}",
                "A cultural heritage village photo of {desc}",
            ],
            '천': [
                "An urban stream photo of {desc}",
                "A waterway photo of {desc}",
                "A restored stream photo of {desc}",
                "A downtown Seoul stream photo of {desc}",
            ],
            '문': [
                "A traditional Korean gate photo of {desc}",
                "A historical entrance photo of {desc}",
                "A palace gate photo of {desc}",
                "An ancient architecture photo of {desc}",
            ]
        }
    
    def get_variations(self, english_desc, korean_name):
        """주어진 장소에 대한 다양한 텍스트 설명 생성"""
        variations = []
        
        # 기본 변형 추가
        for template in self.base_variations:
            variations.append(template.format(desc=english_desc))
        
        # 관광지 유형별 특화 설명 추가
        for key, templates in self.specialized_descriptions.items():
            if key in korean_name:
                for template in templates:
                    variations.append(template.format(desc=english_desc))
                break
        
        return variations

# 사전 정의된 증강 설정
class AugmentationPresets:
    """다양한 증강 설정 프리셋"""
    
    @staticmethod
    def light_augmentation():
        """가벼운 증강 (검증용)"""
        return TouristPhotoAugmentation(probability=0.3)
    
    @staticmethod
    def moderate_augmentation():
        """중간 증강 (일반 훈련용)"""
        return TouristPhotoAugmentation(probability=0.6)
    
    @staticmethod
    def heavy_augmentation():
        """강한 증강 (데이터 부족시)"""
        return TouristPhotoAugmentation(probability=0.8)
    
    @staticmethod
    def no_augmentation():
        """증강 없음 (테스트용)"""
        return TouristPhotoAugmentation(probability=0.0)

# 사용 예시
if __name__ == "__main__":
    # 테스트용 코드
    from PIL import Image
    
    # 샘플 이미지 로드 (실제 이미지 경로로 변경)
    try:
        sample_image = Image.open("database_images/경복궁/gyeongbokgung-1403413_1280.jpg")
        
        # 증강 적용
        augmentation = AugmentationPresets.moderate_augmentation()
        augmented_image = augmentation(sample_image)
        
        # 결과 저장
        augmented_image.save("augmented_sample.jpg")
        print("✅ 증강 테스트 완료! augmented_sample.jpg 파일을 확인하세요.")
        
    except FileNotFoundError:
        print("⚠️ 테스트 이미지를 찾을 수 없습니다. 실제 이미지 경로를 확인하세요.")
    
    # 텍스트 증강 테스트
    text_aug = TextAugmentation()
    variations = text_aug.get_variations(
        "Gyeongbokgung Palace, a royal palace in Seoul", 
        "경복궁"
    )
    
    print("\n📝 텍스트 증강 예시:")
    for i, var in enumerate(variations[:5], 1):
        print(f"  {i}. {var}")
