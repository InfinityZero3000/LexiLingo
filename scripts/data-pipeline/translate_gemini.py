import json
import time
import requests
import sys
import random
import re

API_KEYS = [
    "AIzaSyA7KgjM3Jt3E09RudKLUcA6e0WO4YOW2vY",
    "AIzaSyCiKyxQERiVTEmlwa4euWOlQdlFo6UKLSo",
    "AIzaSyBGjPwt7QLrZz4NgLUHnRts1E12yJEVgNQ",
    "AIzaSyB_tii-C0tZEr4yEIsiCCtQQ_kx1o-SJLw"
]

FILE_PATH = "/opt/lexilingo/scripts/categorized_words_final.json"

def needs_translation(entry):
    trans = entry.get("translation", {})
    if not trans:
        return True
    
    for lang in ["en", "vi", "ja", "ko", "zh", "fr", "es"]:
        val = trans.get(lang, "")
        if not isinstance(val, str) or not val.strip() or "#N/A" in val or "N/A" in val or "yet" in val:
            return True
    return False

def clean_json_response(text):
    text = text.strip()
    if text.startswith("```json"):
        text = text[7:]
    if text.startswith("```"):
        text = text[3:]
    if text.endswith("```"):
        text = text[:-3]
    return text.strip()

def process_batch(batch):
    prompt = """Translate these words into multiple languages. I will give you the word and its english definition for context.
You MUST return ONLY a JSON array containing objects. Each object MUST have:
1. 'word' (the english word)
2. 'translation' (an object with keys 'en' (short english meaning), 'vi' (vietnamese meaning), 'ja' (japanese), 'ko' (korean), 'zh' (chinese), 'fr' (french), 'es' (spanish)).

Ensure all translations are natural and accurate. For 'vi', make sure it is 100% Vietnamese.
Return ONLY valid JSON.
"""
    
    input_data = [{"word": e.get('word', ''), "definition": e.get('definition', '')} for e in batch]
    prompt += "\nInput words:\n" + json.dumps(input_data, ensure_ascii=False)
    
    payload = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {
            "temperature": 0.1,
        }
    }
    
    for attempt in range(5):
        key = random.choice(API_KEYS)
        url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent?key={key}"
        
        try:
            resp = requests.post(url, headers={"Content-Type": "application/json"}, json=payload)
            if resp.status_code == 200:
                try:
                    text = resp.json()['candidates'][0]['content']['parts'][0]['text']
                    text = clean_json_response(text)
                    return json.loads(text)
                except Exception as e:
                    print(f"JSON Parse error (Attempt {attempt+1}):", e)
                    # Retry instead of failing
                    time.sleep(2)
            elif resp.status_code == 429:
                print(f"Rate limited. Retrying with another key... (Attempt {attempt+1})")
                time.sleep(2)
            else:
                print(f"Error {resp.status_code}: {resp.text}")
                time.sleep(2)
        except Exception as e:
            print("Request crashed:", e)
            time.sleep(2)
            
    return []

def main():
    try:
        with open(FILE_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        print("Could not read file:", e)
        sys.exit(1)

    missing_indices = [i for i, entry in enumerate(data) if needs_translation(entry)]
    print(f"Found {len(missing_indices)} words missing translation or containing #N/A yet.")
    
    if not missing_indices:
        print("All words are fully translated!")
        sys.exit(0)

    batch_size = 15
    total_batches = (len(missing_indices) + batch_size - 1) // batch_size

    for i in range(0, len(missing_indices), batch_size):
        batch_idxs = missing_indices[i:i+batch_size]
        batch = [data[idx] for idx in batch_idxs]

        print(f"Processing batch {i//batch_size + 1}/{total_batches} ({len(batch)} words)...")

        results = process_batch(batch)
        
        if not results:
            print("Failed to get results for this batch after multiple retries. Skipping for now...")
            continue

        res_dict = {item.get('word', '').lower(): item.get('translation', {}) for item in results if isinstance(item, dict)}

        updated_count = 0
        for idx in batch_idxs:
            w = data[idx].get('word', '').lower()
            if w in res_dict:
                new_trans = res_dict[w]
                if 'translation' not in data[idx]:
                    data[idx]['translation'] = {}
                
                for lang in ["en", "vi", "ja", "ko", "zh", "fr", "es"]:
                    if lang in new_trans and new_trans[lang]:
                        val = new_trans[lang]
                        if "#N/A" not in val and val.strip():
                            data[idx]['translation'][lang] = val.strip()
                updated_count += 1
                
        print(f"-> Successfully updated {updated_count} words.")

        with open(FILE_PATH, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

        time.sleep(1)

    print("Gemini translation backfill is complete!")

if __name__ == "__main__":
    main()
