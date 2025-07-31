"""
관광지 관련 공통 설정 및 유틸리티 함수
"""
from math import radians, sin, cos, sqrt, atan2

# 관광지 좌표 (위도, 경도)
PLACE_COORDINATES = {
    '경복궁': (37.5796, 126.9770),
    '경희궁': (37.5704, 126.9682),
    '광화문': (37.5725, 126.9768),
    '남산서울타워': (37.5511, 126.9882),
    '북촌한옥마을': (37.5825, 126.9849),
    '청계천': (37.5697, 126.9975),
    '독립문': (37.5725, 126.9595),
    '서울도서관': (37.5664, 126.9780)
}

# 장소 매핑 (한글 -> 영어)
PLACE_MAPPING = {
    '경복궁': 'Gyeongbokgung Palace',
    '경희궁': 'Gyeonghui Palace', 
    '광화문': 'Gwanghwamun Gate',
    '남산서울타워': 'Namsan Seoul Tower',
    '북촌한옥마을': 'Bukchon Hanok Village',
    '청계천': 'Cheonggyecheon Stream',
    '독립문': 'Independence Gate',
    '서울도서관': 'Seoul Metropolitan Library'
}

def calculate_distance_km(lat1, lon1, lat2, lon2):
    """Haversine 공식을 사용한 두 지점 간의 거리 계산 (km)"""
    R = 6371  # 지구의 반경 (km)
    
    lat1, lon1, lat2, lon2 = map(radians, [lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    
    a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlon/2)**2
    c = 2 * atan2(sqrt(a), sqrt(1-a))
    distance = R * c
    
    return distance 