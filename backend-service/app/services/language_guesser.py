import re

def guess_language_from_name(full_name: str) -> str:
    """
    Heuristically guesses the target language ('en', 'vi', 'ja', 'ko', 'zh', 'fr', 'es') 
    from a user's full name based on script ranges or common surnames.
    Default fallback is 'en'.
    """
    if not full_name:
        return 'en'
        
    name_clean = full_name.strip()
    
    # 1. Unicode Range Detection (Highly accurate for Asian scripts)
    # Japanese (Hiragana, Katakana)
    if re.search(r'[\u3040-\u309F\u30A0-\u30FF]', name_clean):
        return 'ja'
        
    # Korean (Hangul)
    if re.search(r'[\uAC00-\uD7AF\u1100-\u11FF]', name_clean):
        return 'ko'
        
    # Chinese (Hanzi - simplified / traditional)
    # Note: Chinese characters can also be used in Japanese (Kanji). 
    # Since we checked Kana above, remaining Hanzi can strongly lean towards Chinese, 
    # but could be a full-Kanji Japanese name. We'll default to 'zh' if purely Hanzi.
    if re.search(r'[\u4E00-\u9FFF]', name_clean):
        # We can implement a common Chinese surname check vs Japanese Kanji surname check here, 
        # but for simplicity we return 'zh'.
        return 'zh'
        
    # Vietnamese (Checking for common Vietnamese diacritics)
    if re.search(r'[áàảãạăắằẳẵặâấầẩẫậéèẻẽẹêếềểễệíìỉĩịóòỏõọôốồổỗộơớờởỡợúùủũụưứừửữựýỳỷỹỵđ]', name_clean, re.IGNORECASE):
        return 'vi'

    # 2. Latin-based Surname / Given name Heuristics (Romanized names)
    name_lower = name_clean.lower()
    parts = re.split(r'\s+', name_lower)
    
    # Common Vietnamese surnames
    vi_surnames = {"nguyen", "tran", "le", "pham", "hoang", "huynh", "phan", "vu", "vo", "dang", "bui", "do", "ho", "ngo", "duong", "ly"}
    
    # Common Spanish surnames
    es_surnames = {"garcia", "rodriguez", "gonzalez", "fernandez", "lopez", "martinez", "sanchez", "perez", "gomez", "martin", "diaz"}
    
    # Common French surnames
    fr_surnames = {"martin", "bernard", "thomas", "petit", "robert", "richard", "durand", "dubois", "moreau", "laurent", "simon"}
    
    # Common Korean Romanized names
    ko_surnames = {"kim", "lee", "park", "choi", "jung", "jeong", "kang", "cho", "yoon", "jang", "lim", "shin", "hwang"}
    
    # Common Chinese Romanized names
    zh_surnames = {"wang", "li", "zhang", "liu", "chen", "yang", "huang", "zhao", "wu", "zhou", "xu", "sun", "ma", "zhu", "hu"}

    # Common Japanese Romaji
    ja_surnames = {"sato", "suzuki", "takahashi", "tanaka", "watanabe", "ito", "yamamoto", "nakamura", "kobayashi", "kato"}

    # Check intersection
    name_set = set(parts)
    
    if name_set.intersection(vi_surnames): return 'vi'
    if name_set.intersection(es_surnames): return 'es'
    if name_set.intersection(fr_surnames): return 'fr'
    if name_set.intersection(ko_surnames): return 'ko'
    if name_set.intersection(zh_surnames): return 'zh'
    if name_set.intersection(ja_surnames): return 'ja'

    # Fallback to English
    return 'en'
