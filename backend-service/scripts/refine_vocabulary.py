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
MODEL = "llama-3.3-70b-versatile"

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

def is_cjk(c):
    codepoint = ord(c)
    return (
        0x4E00 <= codepoint <= 0x9FFF or
        0x3400 <= codepoint <= 0x4DBF or
        0x20000 <= codepoint <= 0x2A6DF or
        0x2A700 <= codepoint <= 0x2B73F or
        0x2B740 <= codepoint <= 0x2B81F or
        0x2B820 <= codepoint <= 0x2CEAF or
        0xF900 <= codepoint <= 0xFAFF
    )

def clean_vietnamese_translation(text):
    if not isinstance(text, str):
        return text
    # Remove any CJK characters
    text = "".join(c for c in text if not is_cjk(c))
    # Clean duplicate commas and spaces
    text = re.sub(r',\s*,', ',', text)
    text = re.sub(r'\s+', ' ', text)
    text = re.sub(r'^\s*,\s*|\s*,\s*$', '', text)
    text = re.sub(r',\s*,\s*', ', ', text)
    return text.strip()

def needs_refinement(item):
    defn = item.get("definition", "").strip()
    if not defn:
        return True
        
    # Heuristic for English definitions
    english_words = {'is', 'a', 'to', 'of', 'and', 'the', 'it', 'or', 'in', 'with', 'if', 'something', 'describes', 'someone', 'by', 'for', 'from', 'an'}
    words = set(re.findall(r'\b\w+\b', defn.lower()))
    if words.intersection(english_words):
        return True
        
    # Heuristic for short/direct translation definitions (e.g. 'đội, nhóm')
    # If it is less than 15 characters, or contains comma/semicolon, it's a translation, not explanation.
    if len(defn) < 15 or ',' in defn or ';' in defn:
        return True
        
    trans_vi = item.get("translation", {}).get("vi", "")
    if not trans_vi or any(is_cjk(c) for c in str(trans_vi)):
        return True
        
    return False

def clean_json_wrapper(text):
    text = text.strip()
    if text.startswith("```json"):
        text = text[7:]
    if text.startswith("```"):
        text = text[3:]
    if text.endswith("```"):
        text = text[:-3]
    return text.strip()

def fetch_refinements_batch(batch_items):
    prompt = (
        "You are an expert bilingual lexicographer. I will provide a JSON list of English words, their definition (which might be in English or a short translation), and their current Vietnamese translation.\n"
        "For each word, you must return a JSON object with two fields:\n"
        "1. \"definition\": A concise, natural Vietnamese explanation/definition of the word's meaning (suitable for language learners, e.g. \"Một nhóm người hợp tác cùng nhau để làm việc hoặc chơi thể thao\" for \"team\"). It must be a full explanation, NOT a direct 1-3 word translation.\n"
        "2. \"translation_vi\": A clean Vietnamese direct translation (synonym or equivalent words, e.g., \"đội, nhóm\" for \"team\"), with NO CJK/Chinese/Hán/Nom characters (e.g. remove characters like 學, 實, 體).\n"
        "\n"
        "Return ONLY a valid JSON object where keys are the words and values are their corresponding objects containing \"definition\" and \"translation_vi\". "
        "Do NOT return any other text or explanation."
    )
    
    user_payload = []
    for item in batch_items:
        user_payload.append({
            "word": item.get("word"),
            "definition": item.get("definition", ""),
            "translation_vi": item.get("translation", {}).get("vi", "")
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
            print(f"Key index {current_key_idx-1} failed (HTTP {e.code}). Msg: {err_msg[:100]}...")
            time.sleep(1.0)
        except Exception as e:
            print(f"Key index {current_key_idx-1} failed (Generic error): {e}")
            time.sleep(1.0)
            
    return None

def main():
    print("Step 1: Reading JSON...")
    if not os.path.exists(FILE_PATH):
        print(f"Error: {FILE_PATH} does not exist.")
        return
        
    with open(FILE_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)
        
    print(f"Loaded {len(data)} items.")
    
    # Local passes: Clean CJK characters from translation['vi'] immediately
    print("Step 2: Performing local Hán/Nom character sanitization...")
    local_cleaned_count = 0
    for item in data:
        trans = item.get("translation", {})
        if isinstance(trans, dict):
            vi = trans.get("vi", "")
            if isinstance(vi, str) and any(is_cjk(c) for c in vi):
                trans["vi"] = clean_vietnamese_translation(vi)
                local_cleaned_count += 1
                
    print(f"-> Sanitized Hán/Nom characters locally for {local_cleaned_count} items.")
    
    # Scan for items needing semantic refinement
    to_refine_indices = [idx for idx, item in enumerate(data) if needs_refinement(item)]
    print(f"Step 3: Found {len(to_refine_indices)} items needing explanation and translation refinement.")
    
    if not to_refine_indices:
        print("No items need refinement!")
        return
        
    batch_size = 50
    total_batches = (len(to_refine_indices) + batch_size - 1) // batch_size
    
    for i in range(0, len(to_refine_indices), batch_size):
        batch_idxs = to_refine_indices[i:i+batch_size]
        batch_items = [data[idx] for idx in batch_idxs]
        
        print(f"Refining batch {i//batch_size + 1}/{total_batches} ({len(batch_items)} words)...")
        
        refinements_map = None
        retries = 3
        while retries > 0:
            refinements_map = fetch_refinements_batch(batch_items)
            if refinements_map:
                break
            retries -= 1
            print(f"Retrying batch... ({retries} retries left)")
            time.sleep(2.0)
            
        if not refinements_map:
            print("Skipping batch because of repeated API failures.")
            continue
            
        # Standardize keys to lowercase
        refinements_map_lower = {k.lower().strip(): v for k, v in refinements_map.items() if isinstance(v, dict)}
        
        updated_in_batch = 0
        for idx in batch_idxs:
            item = data[idx]
            w = item.get("word", "").lower().strip()
            
            ref = refinements_map_lower.get(w)
            if not ref:
                # Fallback: check stripped word
                cleaned_word = re.sub(r"[^\w\s-]", "", w).strip()
                ref = refinements_map_lower.get(cleaned_word)
                
            if ref and isinstance(ref, dict):
                new_def = ref.get("definition", "").strip()
                new_trans_vi = ref.get("translation_vi", "").strip()
                
                if new_def:
                    item["definition"] = new_def
                if new_trans_vi:
                    if "translation" not in item:
                        item["translation"] = {}
                    item["translation"]["vi"] = clean_vietnamese_translation(new_trans_vi)
                
                updated_in_batch += 1
                
        print(f"-> Successfully refined {updated_in_batch}/{len(batch_items)} words.")
        
        # Progressive save
        with open(FILE_PATH, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        print("  Saved batch updates.")
        
        time.sleep(1.0)
        
    print("Refinement process complete!")

if __name__ == "__main__":
    main()
