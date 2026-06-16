#!/usr/bin/env python3
import json
import os
import re
import ssl
import time
import urllib.request
import urllib.parse
import urllib.error

FILE_PATH = "/opt/lexilingo/backend-service/data/vocabulary_import.json"
GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
MODEL = "llama-3.1-8b-instant"

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

current_key_idx = 0

def get_next_api_key():
    global current_key_idx
    key = API_KEYS[current_key_idx]
    current_key_idx = (current_key_idx + 1) % len(API_KEYS)
    return key

# Standard Vietnamese accent characters
ACCENT_CHARS = set('áàảãạăắằẳẵặâấầẩẫậéèẻẽẹêếềểễệíìỉĩịóòỏõọôốồổỗộơớờởỡợúùủũụưứừửữựýỳỷỹỵđ')

def has_accents(text):
    if not isinstance(text, str):
        return True
    return any(c in ACCENT_CHARS for c in text.lower())

def clean_json_wrapper(text):
    text = text.strip()
    if text.startswith("```json"):
        text = text[7:]
    if text.startswith("```"):
        text = text[3:]
    if text.endswith("```"):
        text = text[:-3]
    return text.strip()

def fetch_accents_batch(batch_items):
    prompt = (
        "You are an expert Vietnamese linguist. I will provide a JSON list of English words and their current Vietnamese translation (which is missing accents/diacritics, e.g., \"hoc\" for \"learn\", \"chinh sach\" for \"policy\", \"nuoc\" for \"water\").\n"
        "For each word, you must correct the Vietnamese translation by adding the proper Vietnamese accents (dấu tiếng Việt) so it is grammatically correct and matches the meaning (e.g. \"hoc\" -> \"học\", \"chinh sach\" -> \"chính sách\", \"nuoc\" -> \"nước\", \"tuoi\" -> \"tuổi\").\n"
        "If the current translation is already correct and naturally does not need accents (e.g. \"cho\" for \"give\", \"kinh doanh\" for \"business\"), keep it as is.\n"
        "\n"
        "Return ONLY a valid JSON object where keys are words and values are the corrected Vietnamese translation strings. "
        "Do NOT return any other text or explanation."
    )
    
    user_payload = []
    for item in batch_items:
        user_payload.append({
            "word": item.get("word"),
            "current_translation_vi": item.get("translation", {}).get("vi", "")
        })
        
    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": prompt},
            {"role": "user", "content": json.dumps(user_payload, ensure_ascii=False)}
        ],
        "temperature": 0.1,
        "response_format": {"type": "json_object"}
    }
    
    # Try multiple API keys
    for attempt in range(len(API_KEYS) * 2):
        api_key = get_next_api_key()
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "User-Agent": "Mozilla/5.0"
        }
        
        req = urllib.request.Request(
            GROQ_URL, 
            data=json.dumps(payload).encode("utf-8"), 
            headers=headers, 
            method="POST"
        )
        
        try:
            context = ssl._create_unverified_context()
            with urllib.request.urlopen(req, context=context) as response:
                res_data = json.loads(response.read().decode("utf-8"))
                raw_content = res_data["choices"][0]["message"]["content"]
                cleaned = clean_json_wrapper(raw_content)
                return json.loads(cleaned)
        except urllib.error.HTTPError as e:
            try:
                err_msg = e.read().decode("utf-8")
            except Exception:
                err_msg = ""
            actual_key_idx = (current_key_idx - 1) % len(API_KEYS)
            print(f"Key index {actual_key_idx} failed (HTTP {e.code}). Msg: {err_msg[:100]}...")
            if e.code == 429:
                print("Rate limit (429) hit. Waiting 6.0 seconds before rotating to the next key...")
                time.sleep(6.0)
            else:
                time.sleep(1.5)
        except Exception as e:
            actual_key_idx = (current_key_idx - 1) % len(API_KEYS)
            print(f"Key index {actual_key_idx} failed (Generic error): {e}")
            time.sleep(1.5)
            
    return None

def main():
    print("Step 1: Reading JSON...")
    if not os.path.exists(FILE_PATH):
        print(f"Error: {FILE_PATH} does not exist.")
        return
        
    with open(FILE_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)
        
    print(f"Loaded {len(data)} items.")
    
    # Identify items needing accents
    to_correct_indices = []
    for idx, item in enumerate(data):
        vi = item.get("translation", {}).get("vi", "")
        if isinstance(vi, str) and not has_accents(vi):
            to_correct_indices.append(idx)
            
    print(f"Step 2: Found {len(to_correct_indices)} items needing Vietnamese accent correction.")
    
    if not to_correct_indices:
        print("No items need accent correction!")
        return
        
    batch_size = 30
    total_batches = (len(to_correct_indices) + batch_size - 1) // batch_size
    
    for i in range(0, len(to_correct_indices), batch_size):
        batch_idxs = to_correct_indices[i:i+batch_size]
        batch_items = [data[idx] for idx in batch_idxs]
        
        print(f"Correcting batch {i//batch_size + 1}/{total_batches} ({len(batch_items)} words)...")
        
        corrections_map = None
        retries = 5
        while retries > 0:
            corrections_map = fetch_accents_batch(batch_items)
            if corrections_map:
                break
            retries -= 1
            print(f"Retrying batch... ({retries} retries left)")
            time.sleep(4.0)
            
        if not corrections_map:
            print("Skipping batch because of repeated API failures.")
            continue
            
        # Standardize keys to lowercase
        corrections_map_lower = {k.lower().strip(): v for k, v in corrections_map.items() if isinstance(v, str)}
        
        updated_in_batch = 0
        for idx in batch_idxs:
            item = data[idx]
            w = item.get("word", "").lower().strip()
            
            corrected_vi = corrections_map_lower.get(w)
            if not corrected_vi:
                # Fallback check stripped word
                cleaned_word = re.sub(r"[^\w\s-]", "", w).strip()
                corrected_vi = corrections_map_lower.get(cleaned_word)
                
            if corrected_vi and isinstance(corrected_vi, str):
                item["translation"]["vi"] = corrected_vi.strip()
                updated_in_batch += 1
                
        print(f"-> Successfully restored accents for {updated_in_batch}/{len(batch_items)} words.")
        
        # Progressive save
        with open(FILE_PATH, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        print("  Saved batch updates.")
        
        # Protect against Groq rate limit (TPM/RPM)
        time.sleep(2.5)
        
    print("Accent restoration process complete!")

if __name__ == "__main__":
    main()
