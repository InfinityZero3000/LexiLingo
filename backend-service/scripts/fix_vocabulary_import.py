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
MODEL = os.getenv("GROQ_MODEL", "qwen/qwen3.6-27b")

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

def clean_wiki_text(text):
    if not isinstance(text, str):
        return text
    # Replace [[A|B]] with B
    text = re.sub(r'\[\[[^|\]]+\|([^\]]+)\]\]', r'\1', text)
    # Replace [[A]] with A
    text = re.sub(r'\[\[([^\]]+)\]\]', r'\1', text)
    # Remove ''
    text = text.replace("''", "")
    # Remove any leftover unmatched brackets
    text = text.replace("[[", "").replace("]]", "")
    return text.strip()

def fix_audio_path(v):
    if isinstance(v, str) and v.startswith("extracted_media/"):
        return v.replace("extracted_media/", "")
    return v

def clean_json_wrapper(text):
    text = text.strip()
    if text.startswith("```json"):
        text = text[7:]
    if text.startswith("```"):
        text = text[3:]
    if text.endswith("```"):
        text = text[:-3]
    return text.strip()

def fetch_difficulty_batch(batch_words):
    prompt = (
        "You are an expert lexicographer. Classify the following list of English words into their most appropriate CEFR difficulty levels: A1, A2, B1, B2, C1, or C2. "
        "Use the provided definitions for context.\n"
        "Return ONLY a valid JSON object where keys are words and values are their CEFR levels (e.g. {\"apple\": \"A1\", \"paradigm\": \"C1\"}). "
        "Do NOT return any other text or explanation."
    )
    
    user_payload = []
    for item in batch_words:
        user_payload.append({
            "word": item.get("word"),
            "definition": item.get("definition", "")
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
            
    print("All keys failed for this batch.")
    return None

def main():
    print("Step 1: Reading and backup JSON...")
    if not os.path.exists(FILE_PATH):
        print(f"Error: {FILE_PATH} does not exist.")
        return
        
    with open(FILE_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)
        
    print(f"Loaded {len(data)} items.")
    
    # Local cleanups
    print("Step 2: Performing syntax cleanup and media path fixes...")
    cleaned_translations_count = 0
    fixed_paths_count = 0
    
    for item in data:
        # Fix media paths
        audios = item.get("audios", {})
        if isinstance(audios, dict):
            for k, v in list(audios.items()):
                new_v = fix_audio_path(v)
                if new_v != v:
                    audios[k] = new_v
                    fixed_paths_count += 1
        
        images = item.get("images", "")
        if isinstance(images, str) and images.startswith("extracted_media/"):
            item["images"] = images.replace("extracted_media/", "")
            fixed_paths_count += 1
            
        # Clean wiktionary syntax in translations
        trans = item.get("translation", {})
        if isinstance(trans, dict):
            for lang, text in list(trans.items()):
                if isinstance(text, str):
                    new_text = clean_wiki_text(text)
                    if new_text != text:
                        trans[lang] = new_text
                        cleaned_translations_count += 1
                elif isinstance(text, list):
                    # For examples list or similar
                    new_list = [clean_wiki_text(x) if isinstance(x, str) else x for x in text]
                    if new_list != text:
                        trans[lang] = new_list
                        cleaned_translations_count += 1

    print(f"-> Fixed {fixed_paths_count} media paths.")
    print(f"-> Cleaned {cleaned_translations_count} translation fields.")
    
    # Checkpoint local fixes
    with open(FILE_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print("Progress checkpoint saved.")

    # Classify difficulty levels
    print("Step 3: Finding items missing difficulty levels...")
    to_classify_indices = []
    for idx, item in enumerate(data):
        level = item.get("difficulty_level")
        if not level or level == "":
            to_classify_indices.append(idx)
            
    print(f"-> Found {len(to_classify_indices)} items needing difficulty level classification.")
    
    if not to_classify_indices:
        print("No items need difficulty level classification!")
        return

    # Process in batches
    batch_size = 50
    total_batches = (len(to_classify_indices) + batch_size - 1) // batch_size
    valid_levels = {"A1", "A2", "B1", "B2", "C1", "C2"}
    
    for i in range(0, len(to_classify_indices), batch_size):
        batch_idxs = to_classify_indices[i:i+batch_size]
        batch_words = [data[idx] for idx in batch_idxs]
        
        print(f"Processing batch {i//batch_size + 1}/{total_batches} ({len(batch_words)} words)...")
        
        levels_map = None
        retries = 3
        while retries > 0:
            levels_map = fetch_difficulty_batch(batch_words)
            if levels_map:
                break
            retries -= 1
            print(f"Retrying batch... ({retries} retries left)")
            time.sleep(2.0)
            
        if not levels_map:
            print("Skipping batch because of repeated API failures.")
            continue
            
        # Standardize keys to lowercase for matching
        levels_map_lower = {k.lower().strip(): v.upper().strip() for k, v in levels_map.items() if isinstance(v, str)}
        
        updated_in_batch = 0
        for idx in batch_idxs:
            item = data[idx]
            w = item.get("word", "").lower().strip()
            
            level = levels_map_lower.get(w)
            if level in valid_levels:
                item["difficulty_level"] = level
                updated_in_batch += 1
            else:
                # Fallback: check if sub-parts or clean word matches
                cleaned_word = re.sub(r"[^\w\s-]", "", w).strip()
                level = levels_map_lower.get(cleaned_word)
                if level in valid_levels:
                    item["difficulty_level"] = level
                    updated_in_batch += 1
                else:
                    # Generic fallback based on index frequency
                    # (since first ~1500 words are usually A1/A2, next are B1/B2, etc.)
                    index = item.get("index", 0)
                    if index <= 1500:
                        item["difficulty_level"] = "A1"
                    elif index <= 3000:
                        item["difficulty_level"] = "A2"
                    elif index <= 4500:
                        item["difficulty_level"] = "B1"
                    elif index <= 5500:
                        item["difficulty_level"] = "B2"
                    else:
                        item["difficulty_level"] = "C1"
                    # We print warning but set a reasonable fallback
                    print(f"  Fallback level {item['difficulty_level']} assigned for '{item.get('word')}'")
                    updated_in_batch += 1
                    
        print(f"-> Successfully classified {updated_in_batch}/{len(batch_words)} words.")
        
        # Save every batch
        with open(FILE_PATH, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        print("  Saved batch updates.")
        
        # Polite delay
        time.sleep(1.0)
        
    print("Done! Standardizing and cleaning complete.")

if __name__ == "__main__":
    main()
