import torch
import clip
from PIL import Image
import os
from tqdm import tqdm
from clip_lora_finetuning import LoRACLIP, LoRALayer  # LoRA 모델 클래스 import
import numpy as np
from math import radians, sin, cos, sqrt, atan2

class CLIPLoRAInference:
    def __init__(self, model_path="fine_tuned_model_train_test_split/20_places_new_best_model.pth"):
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        print(f"🚀 장치: {self.device}")
        
        # CLIP 모델 로드 (float32로)
        self.clip_model, self.preprocess = clip.load("ViT-B/32", device=self.device)
        self.clip_model = self.clip_model.float()
        
        # LoRA 모델 로드
        self.load_lora_model(model_path)
        
        # 20개 관광지 매핑 (한글 -> 영어)
        self.place_mapping = {
            '경복궁': 'Gyeongbokgung Palace',
            '경희궁': 'Gyeonghui Palace', 
            '광화문': 'Gwanghwamun Gate',
            '남산서울타워': 'Namsan Seoul Tower',
            '북촌한옥마을': 'Bukchon Hanok Village',
            '청계천': 'Cheonggyecheon Stream',
            '독립문': 'Independence Gate',
            '서울도서관': 'Seoul Metropolitan Library',
            '숭례문': 'Sungnyemun Gate',
            '덕수궁': 'Deoksugung Palace',
            '창경궁': 'Changgyeonggung Palace',
            '롯데타워': 'Lotte Tower',
            '서울숲': 'Seoul Forest',
            '봉은사': 'Bongeunsa Temple',
            '올림픽공원_들꽃마루': 'Olympic Park Flower Garden',
            '낙산공원': 'Naksan Park',
            '노들섬': 'Nodeulseom Island',
            '창덕궁': 'Changdeokgung Palace',
            '동대문디자인플라자': 'Dongdaemun Design Plaza',
            '은평한옥마을': 'Eunpyeong Hanok Village'
        }
        
        # 텍스트 임베딩 미리 계산
        self.text_features = self.encode_text_descriptions()
        
        # 20개 관광지별 좌표 추가 (위도, 경도)
        self.place_coords = {
            '경복궁': (37.5796, 126.9770),
            '경희궁': (37.5704, 126.9682),
            '광화문': (37.5725, 126.9768),
            '남산서울타워': (37.5511, 126.9882),
            '북촌한옥마을': (37.5825, 126.9849),
            '청계천': (37.5697, 126.9975),
            '독립문': (37.5725, 126.9595),
            '서울도서관': (37.5664, 126.9780),
            '숭례문': (37.5611, 126.9755),
            '덕수궁': (37.5658, 126.9750),
            '창경궁': (37.5786, 126.9949),
            '롯데타워': (37.5135, 127.1026),
            '서울숲': (37.5446, 127.0370),
            '봉은사': (37.5135, 127.0590),
            '올림픽공원_들꽃마루': (37.5214, 127.1278),
            '낙산공원': (37.5806, 127.0089),
            '노들섬': (37.5167, 126.9333),
            '창덕궁': (37.5794, 126.9910),
            '동대문디자인플라자': (37.5665, 127.0090),
            '은평한옥마을': (37.6414, 126.9270)
        }
        
        print("✅ 20개 관광지 모델 준비 완료!")
    
    def load_lora_model(self, model_path):
        """LoRA 모델 로드"""
        if not os.path.exists(model_path):
            raise FileNotFoundError(f"❌ 모델 파일을 찾을 수 없습니다: {model_path}")
        
        # 체크포인트 로드
        checkpoint = torch.load(model_path, map_location=self.device)
        
        # LoRA 모델 초기화
        self.model = LoRACLIP(
            self.clip_model,
            rank=checkpoint.get('rank', 16),
            alpha=checkpoint.get('alpha', 32)
        ).to(self.device)
        
        # LoRA 가중치 로드
        if 'lora_state_dict' in checkpoint:
            self.model.load_state_dict(checkpoint['lora_state_dict'], strict=False)
        elif 'model_state_dict' in checkpoint:
            # 전체 모델에서 LoRA 파라미터만 추출
            model_state = checkpoint['model_state_dict']
            lora_state = {k: v for k, v in model_state.items() if 'lora' in k}
            self.model.load_state_dict(lora_state, strict=False)
        
        self.model.eval()
        
        print(f"💾 LoRA 모델 로드됨: {model_path}")
    
    def encode_text_descriptions(self):
        """모든 장소 설명의 텍스트 임베딩 계산"""
        text_inputs = [desc for desc in self.place_mapping.values()]
        text_tokens = clip.tokenize(text_inputs).to(self.device)
        
        with torch.no_grad():
            text_features = self.model.encode_text_with_lora(text_tokens)
            text_features = text_features / text_features.norm(dim=-1, keepdim=True)
        
        return text_features
    
    def calculate_distance(self, lat1, lon1, lat2, lon2):
        """Haversine 공식을 사용한 두 지점 간의 거리 계산 (km)"""
        R = 6371  # 지구의 반지름 (km)
        
        lat1, lon1, lat2, lon2 = map(radians, [lat1, lon1, lat2, lon2])
        dlat = lat2 - lat1
        dlon = lon2 - lon1
        
        a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlon/2)**2
        c = 2 * atan2(sqrt(a), sqrt(1-a))
        distance = R * c
        
        return distance
    
    def get_location_weight(self, user_lat, user_lon, place_name):
        """위치 기반 가중치 계산"""
        place_lat, place_lon = self.place_coords[place_name]
        distance = self.calculate_distance(user_lat, user_lon, place_lat, place_lon)
        
        # 거리에 따른 가중치 강화 (0.3 ~ 1.7 범위로 확장)
        weight = 1.7 - 1.4 / (1 + np.exp(-distance + 0.8))
        return weight
    
    def predict_place(self, image_path, user_lat=None, user_lon=None, top_k=3):
        """위치 정보를 고려한 장소 예측"""
        try:
            # 이미지 로드 및 전처리
            image = Image.open(image_path).convert('RGB')
            image_input = self.preprocess(image).unsqueeze(0).to(self.device)
            
            with torch.no_grad():
                # 이미지 임베딩 계산
                image_features = self.model.encode_image_with_lora(image_input)
                image_features = image_features / image_features.norm(dim=-1, keepdim=True)
                
                # 기본 유사도 계산
                similarity = (100.0 * image_features @ self.text_features.T).softmax(dim=-1)
                
                # 결과 저장을 위한 리스트
                results = []
                
                # 각 장소별 결과 계산
                for idx, (place_kor, place_eng) in enumerate(self.place_mapping.items()):
                    confidence = float(similarity[0][idx]) * 100
                    place_coord = self.place_coords[place_kor]
                    distance = None
                    
                    if user_lat is not None and user_lon is not None:
                        distance = self.calculate_distance(
                            user_lat, user_lon, 
                            place_coord[0], place_coord[1]
                        )
                        
                        # 거리에 따른 점수 계산 (0~1 사이 값)
                        distance_score = 1.0 / (1.0 + distance)  # 거리가 0km면 1.0, 거리가 멀수록 0에 가까워짐
                        
                        # 신뢰도와 거리 점수를 결합
                        combined_score = confidence * distance_score * 2  # 거리 가중치 2배 증가
                    else:
                        combined_score = confidence
                    
                    results.append({
                        'place_kor': place_kor,
                        'place_eng': place_eng,
                        'confidence': confidence,
                        'distance': distance,
                        'combined_score': combined_score
                    })
                
                # 상위 2개의 신뢰도 차이가 20% 이내인 경우
                sorted_by_confidence = sorted(results, key=lambda x: x['confidence'], reverse=True)
                confidence_diff = sorted_by_confidence[0]['confidence'] - sorted_by_confidence[1]['confidence']
                
                final_results = []
                if confidence_diff < 20:  # 차이 기준을 20%로 확대
                    # 거리 기반 점수로 정렬
                    results = sorted(results, key=lambda x: x['combined_score'], reverse=True)
                    
                    print(f"\n 신뢰도 차이({confidence_diff:.2f}%)가 20% 이내여서 거리 가중치가 적용됨:")
                    print(f"   원본 순위:")
                    print(f"   1. {sorted_by_confidence[0]['place_kor']}: {sorted_by_confidence[0]['confidence']:.2f}% ({sorted_by_confidence[0]['distance']:.2f}km)")
                    print(f"   2. {sorted_by_confidence[1]['place_kor']}: {sorted_by_confidence[1]['confidence']:.2f}% ({sorted_by_confidence[1]['distance']:.2f}km)")
                    print(f"   거리 가중치 적용 후:")
                    print(f"   1. {results[0]['place_kor']}: {results[0]['confidence']:.2f}% ({results[0]['distance']:.2f}km)")
                    print(f"   2. {results[1]['place_kor']}: {results[1]['confidence']:.2f}% ({results[1]['distance']:.2f}km)")
                    
                    # 최종 결과 생성
                    for result in results[:top_k]:
                        final_results.append({
                            'place_kor': result['place_kor'],
                            'place_eng': result['place_eng'],
                            'confidence': result['confidence'],
                            'distance': result['distance']
                        })
                else:
                    # 최종 결과 생성
                    for result in sorted_by_confidence[:top_k]:
                        final_results.append({
                            'place_kor': result['place_kor'],
                            'place_eng': result['place_eng'],
                            'confidence': result['confidence'],
                            'distance': result['distance']
                        })
                
                return final_results
                
        except Exception as e:
            print(f"❌ 에러 발생: {e}")
            return None

def test_model_performance():
    """모델 성능 테스트 함수"""
    print("="*60)
    print("🧪 20개 관광지 모델 성능 테스트")
    print("="*60)
    
    # 추론 모델 초기화
    try:
        inferencer = CLIPLoRAInference()
    except Exception as e:
        print(f"❌ 모델 로드 실패: {e}")
        return
    
    # 쿼리 이미지 폴더 경로
    query_folder = "query_images"
    
    if not os.path.exists(query_folder):
        print(f"❌ 쿼리 이미지 폴더를 찾을 수 없습니다: {query_folder}")
        return
    
    # 결과 저장할 딕셔너리
    all_results = {}
    correct_predictions = 0
    total_predictions = 0
    
    # 모든 이미지에 대해 예측
    print(f"\n📸 쿼리 이미지 분석 중...")
    for filename in tqdm(os.listdir(query_folder), desc="이미지 분석"):
        if not filename.lower().endswith(('.jpg', '.jpeg', '.png')):
            continue
            
        image_path = os.path.join(query_folder, filename)
        
        # 파일명에서 실제 장소명 추출 (예: "경복궁_7_공공3유형.jpg" -> "경복궁")
        # 또는 "창경궁.jpg" -> "창경궁"
        # 또는 "경희궁 흥화문_7_공공3유형.JPG" -> "경희궁"
        filename_without_ext = os.path.splitext(filename)[0]  # 확장자 제거
        extracted_place = filename_without_ext.split('_')[0]  # 첫 번째 언더스코어까지
        
        # 공백이 포함된 경우 첫 번째 단어만 사용 (예: "경희궁 흥화문" -> "경희궁")
        actual_place = extracted_place.split(' ')[0]
        
        # 실제 장소에 맞는 사용자 좌표 설정
        if actual_place in inferencer.place_coords:
            user_lat, user_lon = inferencer.place_coords[actual_place]
            print(f"\n📍 {actual_place} 이미지 - 사용자 위치: ({user_lat:.4f}, {user_lon:.4f})")
        else:
            # 해당 장소의 좌표가 없으면 기본값 사용
            user_lat, user_lon = 37.56931, 126.9700  # 시청역 부근
            print(f"\n⚠️ {actual_place} 좌표 정보 없음 - 기본 위치 사용")
            print(f"   사용 가능한 장소: {list(inferencer.place_coords.keys())}")
        
        results = inferencer.predict_place(image_path, user_lat, user_lon)
        
        if results:
            predicted_place = results[0]['place_kor']
            confidence = results[0]['confidence']
            distance = results[0]['distance']
            
            # 정확도 체크 (부분 일치도 허용)
            is_correct = actual_place == predicted_place or predicted_place in actual_place or actual_place in predicted_place
            if is_correct:
                correct_predictions += 1
            total_predictions += 1
            
            print(f"📸 이미지: {filename}")
            print(f"   실제 장소: {actual_place} (추출된 장소명: {extracted_place})")
            print(f"   예측 장소: {predicted_place}")
            print(f"   신뢰도: {confidence:.2f}%")
            print(f"   거리: {distance:.2f}km")
            print(f"   정확도: {'✅' if is_correct else '❌'}")
            
            # 상위 3개 결과 출력
            print("   상위 3개 예측:")
            for i, result in enumerate(results[:3], 1):
                print(f"   {i}. {result['place_kor']} ({result['place_eng']}) - {result['confidence']:.2f}%")
            
            all_results[filename] = {
                'actual': actual_place,
                'extracted_full': extracted_place,
                'predicted': predicted_place,
                'confidence': confidence,
                'distance': distance,
                'is_correct': is_correct,
                'top_3': results[:3],
                'user_location': (user_lat, user_lon)
            }
    
    # 전체 성능 요약
    print("\n" + "="*60)
    print("📊 모델 성능 요약")
    print("="*60)
    
    if total_predictions > 0:
        accuracy = (correct_predictions / total_predictions) * 100
        print(f"🎯 전체 정확도: {accuracy:.2f}% ({correct_predictions}/{total_predictions})")
        
        # 장소별 정확도 계산
        place_accuracy = {}
        for filename, result in all_results.items():
            actual_place = result['actual']
            if actual_place not in place_accuracy:
                place_accuracy[actual_place] = {'correct': 0, 'total': 0}
            
            place_accuracy[actual_place]['total'] += 1
            if result['is_correct']:
                place_accuracy[actual_place]['correct'] += 1
        
        print(f"\n📈 장소별 정확도:")
        for place, stats in place_accuracy.items():
            place_acc = (stats['correct'] / stats['total']) * 100
            print(f"   {place}: {place_acc:.1f}% ({stats['correct']}/{stats['total']})")
        
        # 평균 신뢰도
        avg_confidence = sum(result['confidence'] for result in all_results.values()) / len(all_results)
        print(f"\n📊 평균 신뢰도: {avg_confidence:.2f}%")
        
        # 정확한 예측의 평균 신뢰도
        correct_confidences = [result['confidence'] for result in all_results.values() if result['is_correct']]
        if correct_confidences:
            avg_correct_confidence = sum(correct_confidences) / len(correct_confidences)
            print(f"✅ 정확한 예측의 평균 신뢰도: {avg_correct_confidence:.2f}%")
        
        # 잘못된 예측의 평균 신뢰도
        incorrect_confidences = [result['confidence'] for result in all_results.values() if not result['is_correct']]
        if incorrect_confidences:
            avg_incorrect_confidence = sum(incorrect_confidences) / len(incorrect_confidences)
            print(f"❌ 잘못된 예측의 평균 신뢰도: {avg_incorrect_confidence:.2f}%")
        
        # 거리 기반 분석
        print(f"\n📍 거리 기반 분석:")
        correct_distances = [result['distance'] for result in all_results.values() if result['is_correct']]
        incorrect_distances = [result['distance'] for result in all_results.values() if not result['is_correct']]
        
        if correct_distances:
            avg_correct_distance = sum(correct_distances) / len(correct_distances)
            print(f"   ✅ 정확한 예측의 평균 거리: {avg_correct_distance:.2f}km")
        
        if incorrect_distances:
            avg_incorrect_distance = sum(incorrect_distances) / len(incorrect_distances)
            print(f"   ❌ 잘못된 예측의 평균 거리: {avg_incorrect_distance:.2f}km")
    
    print("\n" + "="*60)
    print("✅ 테스트 완료!")

def main():
    """기존 main 함수 (단순 추론용)"""
    # 추론 모델 초기화
    inferencer = CLIPLoRAInference()
    
    # 테스트를 위한 사용자 위치 (예: 시청역 부근)
    user_lat = 37.56931
    user_lon = 126.9700
    
    # 쿼리 이미지 폴더 경로
    query_folder = "query_images"
    
    if not os.path.exists(query_folder):
        print(f"❌ 쿼리 이미지 폴더를 찾을 수 없습니다: {query_folder}")
        return
    
    # 결과 저장할 딕셔너리
    all_results = {}
    
    # 모든 이미지에 대해 예측
    for filename in tqdm(os.listdir(query_folder), desc=" 이미지 분석 중"):
        if not filename.lower().endswith(('.jpg', '.jpeg', '.png')):
            continue
            
        image_path = os.path.join(query_folder, filename)
        results = inferencer.predict_place(image_path, user_lat, user_lon)
        
        if results:
            print(f"\n📸 이미지: {filename}")
            print("   예측 결과:")
            for i, result in enumerate(results, 1):
                print(f"  {i}. {result['place_kor']} ({result['place_eng']})")
                print(f"     신뢰도: {result['confidence']:.2f}%")
                print(f"     거리: {result['distance']:.2f}km")
            
            all_results[filename] = results
    
    # 전체 결과 요약 (한 번만 출력)
    print("\n📊 전체 결과 요약:")
    for filename, results in all_results.items():
        top_result = results[0]
        print(f"• {filename}: {top_result['place_kor']} (신뢰도: {top_result['confidence']:.2f}%, 거리: {top_result['distance']:.2f}km)")

if __name__ == "__main__":
    # 성능 테스트 실행
    test_model_performance() 