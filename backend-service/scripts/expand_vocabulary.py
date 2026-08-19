import json
import os
import urllib.request
import urllib.parse
import urllib.error
import ssl
import time
import re

JSON_PATH = "/opt/lexilingo/backend-service/data/vocabulary_import.json"
MEDIA_DIR = "/opt/lexilingo/backend-service/data/media"

from dotenv import load_dotenv
from pathlib import Path

# Load env variables
PROJECT_ROOT = Path(__file__).parent.parent.parent
load_dotenv(PROJECT_ROOT / ".env")
if os.getenv("APP_ENV", "").lower() == "production":
    load_dotenv(PROJECT_ROOT / ".env.production", override=False)

raw_keys = os.getenv("GROQ_API_KEYS", "").strip()
API_KEYS = [k.strip() for k in raw_keys.split(",") if k.strip()] if raw_keys else []
if not API_KEYS:
    single = os.getenv("GROQ_API_KEY", "").strip()
    if single:
        API_KEYS = [single]

if not API_KEYS:
    raise ValueError("Neither GROQ_API_KEYS nor GROQ_API_KEY is configured in the environment.")

current_key_index = 0

def get_next_api_key():
    global current_key_index
    key = API_KEYS[current_key_index]
    current_key_index = (current_key_index + 1) % len(API_KEYS)
    return key

def clean_filename(word):
    cleaned = re.sub(r"[^\w\-_]", "", word)
    return cleaned.lower()

def download_audio(url, dest_path):
    if url.startswith("//"):
        url = "https:" + url
    headers = {"User-Agent": "Mozilla/5.0"}
    req = urllib.request.Request(url, headers=headers)
    try:
        context = ssl._create_unverified_context()
        with urllib.request.urlopen(req, context=context) as response:
            with open(dest_path, "wb") as f:
                f.write(response.read())
        return True
    except Exception as e:
        print(f"  Failed to download audio from {url}: {e}")
        return False

def get_audio_and_phonetic_from_api(word):
    url = f"https://api.dictionaryapi.dev/api/v2/entries/en/{urllib.parse.quote(word)}"
    headers = {"User-Agent": "Mozilla/5.0"}
    req = urllib.request.Request(url, headers=headers)
    try:
        context = ssl._create_unverified_context()
        with urllib.request.urlopen(req, context=context) as response:
            data = json.loads(response.read().decode("utf-8"))
            if data and isinstance(data, list):
                phonetics = data[0].get("phonetics", [])
                audio_url = None
                phonetic_text = data[0].get("phonetic", "")
                
                # Try to find phonetic text in entries
                for p in phonetics:
                    if not phonetic_text and p.get("text"):
                        phonetic_text = p.get("text")
                    if p.get("audio"):
                        if not audio_url or "-us" in p.get("audio") or "us.mp3" in p.get("audio"):
                            audio_url = p.get("audio")
                return phonetic_text, audio_url
    except Exception:
        pass
    return None, None

def call_groq(payload):
    url = "https://api.groq.com/openai/v1/chat/completions"
    for _ in range(len(API_KEYS) * 2):
        api_key = get_next_api_key()
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "User-Agent": "Mozilla/5.0"
        }
        req = urllib.request.Request(url, data=json.dumps(payload).encode("utf-8"), headers=headers, method="POST")
        try:
            context = ssl._create_unverified_context()
            with urllib.request.urlopen(req, context=context) as response:
                res_data = json.loads(response.read().decode("utf-8"))
                return res_data["choices"][0]["message"]["content"]
        except urllib.error.HTTPError as e:
            time.sleep(0.5)
        except Exception:
            time.sleep(0.5)
    time.sleep(2.0)
    return None

def generate_words_for_level(level, level_type, count, existing_words):
    print(f"Generating list of {count} words for {level_type} level {level}...")
    prompt = (
        f"Generate a JSON list of exactly {count * 2} common, high-quality, practical English words "
        f"suitable for {level_type} level {level}. "
        f"Return ONLY a raw JSON list of strings, e.g. [\"word1\", \"word2\"]. No extra markdown, explanation, or tags."
    )
    payload = {
        "model": os.getenv("GROQ_MODEL", "qwen/qwen3.6-27b"),
        "messages": [
            {"role": "system", "content": "You are a vocabulary builder. Output ONLY raw JSON lists of strings."},
            {"role": "user", "content": prompt}
        ],
        "temperature": 0.7,
        "reasoning_effort": "none",
    }
    
    res = call_groq(payload)
    if not res:
        return []
        
    try:
        # Strip any markdown code block wraps
        res_clean = res.strip()
        if res_clean.startswith("```json"):
            res_clean = res_clean[7:]
        if res_clean.startswith("```"):
            res_clean = res_clean[3:]
        if res_clean.endswith("```"):
            res_clean = res_clean[:-3]
        res_clean = res_clean.strip()
        
        words = json.loads(res_clean)
        # Filter duplicates
        filtered = []
        for w in words:
            w_clean = w.strip().lower()
            if w_clean and w_clean not in existing_words and w_clean not in filtered:
                filtered.append(w_clean)
        return filtered[:count]
    except Exception as e:
        print(f"Failed to parse word list for level {level}: {e}. Response was: {res}")
        return []

def fetch_details_for_word(word, level, ielts_band=None):
    print(f"Fetching translations and details for word '{word}'...")
    prompt = (
        f"Provide translation and example details for the English word '{word}'.\n"
        f"Format your response as a strict JSON object with the following fields:\n"
        f"{{\n"
        f"  \"definition\": \"A concise, clear English definition suitable for language learners\",\n"
        f"  \"example\": \"A natural, practical English example sentence using the word '{word}'\",\n"
        f"  \"phonetic\": \"IPA phonetic spelling, e.g. /fəˈnɛtɪk/\",\n"
        f"  \"part_of_speech\": \"noun/verb/adjective/adverb/pronoun/preposition/conjunction/interjection/phrase\",\n"
        f"  \"tags\": \"one relevant thematic category like technology, business, food, health, travel, daily_life, science\",\n"
        f"  \"translation\": {{\n"
        f"    \"en\": \"synonym or simple English translation\",\n"
        f"    \"vi\": \"Vietnamese translation\",\n"
        f"    \"ja\": \"Japanese translation\",\n"
        f"    \"ko\": \"Korean translation\",\n"
        f"    \"zh\": \"Chinese translation\",\n"
        f"    \"fr\": \"French translation\",\n"
        f"    \"es\": \"Spanish translation\"\n"
        f"  }}\n"
        f"}}\n"
        f"Return ONLY the raw JSON object. No explanation, quotes, or markdown wrappers."
    )
    
    payload = {
        "model": os.getenv("GROQ_MODEL", "qwen/qwen3.6-27b"),
        "messages": [
            {"role": "system", "content": "You are a lexicographer. Output ONLY raw JSON objects matching the schema."},
            {"role": "user", "content": prompt}
        ],
        "temperature": 0.0,
        "reasoning_effort": "none",
    }
    
    res = call_groq(payload)
    if not res:
        return None
        
    try:
        res_clean = res.strip()
        if res_clean.startswith("```json"):
            res_clean = res_clean[7:]
        if res_clean.startswith("```"):
            res_clean = res_clean[3:]
        if res_clean.endswith("```"):
            res_clean = res_clean[:-3]
        res_clean = res_clean.strip()
        
        details = json.loads(res_clean)
        return details
    except Exception as e:
        print(f"Failed to parse details for '{word}': {e}. Response: {res}")
        return None

def main():
    if not os.path.exists(MEDIA_DIR):
        os.makedirs(MEDIA_DIR, exist_ok=True)

    print("Loading existing vocabulary...")
    with open(JSON_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)
        
    existing_words = set(item["word"].lower().strip() for item in data)
    max_index = max(item.get("index", 0) for item in data)
    
    # Levels configuration
    cefr_levels = ["A1", "A2", "B1", "B2", "C1", "C2"]
    ielts_levels = ["1.0", "2.0", "3.0", "4.0", "5.0", "6.0", "7.0", "8.0", "9.0"]
    
    words_to_generate_cefr = 10  # words per CEFR level
    words_to_generate_ielts = 5  # words per IELTS level
    
    new_items = []
    
    # 1. Generate CEFR words
    for level in cefr_levels:
        words = generate_words_for_level(level, "CEFR", words_to_generate_cefr, existing_words)
        for w in words:
            existing_words.add(w) # prevent duplicates in same run
            
            # Fetch details
            details = fetch_details_for_word(w, level)
            if not details:
                continue
                
            # Dictionary API check
            api_phonetic, api_audio_url = get_audio_and_phonetic_from_api(w)
            
            phonetic = api_phonetic if api_phonetic else details.get("phonetic", "")
            audio_filename = ""
            
            # Download audio if available
            if api_audio_url:
                ext = ".wav" if ".wav" in api_audio_url.lower() else ".mp3"
                filename = f"{clean_filename(w)}{ext}"
                dest_path = os.path.join(MEDIA_DIR, filename)
                print(f"  Downloading pronunciation from Dictionary API: {api_audio_url}")
                if download_audio(api_audio_url, dest_path):
                    audio_filename = filename
            
            # Construct tag string
            tags = details.get("tags", "general")
            # Append CEFR level to tags
            tags = f"{tags},cefr_{level}"
            
            max_index += 1
            item = {
                "word": w,
                "definition": details.get("definition", ""),
                "example": details.get("example", ""),
                "phonetic": phonetic,
                "audios": {"pronunciation": audio_filename} if audio_filename else {},
                "images": "",
                "index": max_index,
                "tags": tags,
                "difficulty_level": level,
                "translation": details.get("translation", {})
            }
            new_items.append(item)
            print(f"  Successfully added CEFR {level} word '{w}'")
            time.sleep(0.5)

    # 2. Generate IELTS words
    for ielts in ielts_levels:
        # Map IELTS to closest CEFR difficulty level
        # IELTS 1.0 - 2.0 -> A1, 3.0 -> A2, 4.0 -> B1, 5.0 - 6.0 -> B2, 7.0 -> C1, 8.0 - 9.0 -> C2
        val = float(ielts)
        if val <= 2.0:
            cefr_mapped = "A1"
        elif val <= 3.5:
            cefr_mapped = "A2"
        elif val <= 4.5:
            cefr_mapped = "B1"
        elif val <= 6.0:
            cefr_mapped = "B2"
        elif val <= 7.5:
            cefr_mapped = "C1"
        else:
            cefr_mapped = "C2"
            
        words = generate_words_for_level(ielts, "IELTS", words_to_generate_ielts, existing_words)
        for w in words:
            existing_words.add(w)
            
            details = fetch_details_for_word(w, cefr_mapped, ielts)
            if not details:
                continue
                
            api_phonetic, api_audio_url = get_audio_and_phonetic_from_api(w)
            phonetic = api_phonetic if api_phonetic else details.get("phonetic", "")
            audio_filename = ""
            
            if api_audio_url:
                ext = ".wav" if ".wav" in api_audio_url.lower() else ".mp3"
                filename = f"{clean_filename(w)}{ext}"
                dest_path = os.path.join(MEDIA_DIR, filename)
                print(f"  Downloading pronunciation: {api_audio_url}")
                if download_audio(api_audio_url, dest_path):
                    audio_filename = filename
            
            tags = details.get("tags", "general")
            # Append CEFR level and IELTS band to tags
            tags = f"{tags},cefr_{cefr_mapped},ielts_{ielts}"
            
            max_index += 1
            item = {
                "word": w,
                "definition": details.get("definition", ""),
                "example": details.get("example", ""),
                "phonetic": phonetic,
                "audios": {"pronunciation": audio_filename} if audio_filename else {},
                "images": "",
                "index": max_index,
                "tags": tags,
                "difficulty_level": cefr_mapped,
                "translation": details.get("translation", {})
            }
            new_items.append(item)
            print(f"  Successfully added IELTS {ielts} (CEFR {cefr_mapped}) word '{w}'")
            time.sleep(0.5)
            
    if new_items:
        data.extend(new_items)
        with open(JSON_PATH, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        print(f"Successfully added {len(new_items)} new vocabulary items to {JSON_PATH}!")
    else:
        print("No new vocabulary items were generated.")

if __name__ == "__main__":
    main()
