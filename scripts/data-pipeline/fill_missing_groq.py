import os
import json
import time
import requests
import sys

# Get API keys from environment variable (comma-separated), fallback to empty list
api_keys_env = os.getenv("GROQ_API_KEYS", "")
API_KEYS = [k.strip() for k in api_keys_env.split(",") if k.strip()]
if not API_KEYS:
    single_key = os.getenv("GROQ_API_KEY", "")
    if single_key:
        API_KEYS = [single_key]
    else:
        API_KEYS = []
current_key_idx = 0

def get_next_key():
    global current_key_idx
    key = API_KEYS[current_key_idx]
    current_key_idx = (current_key_idx + 1) % len(API_KEYS)
    return key
    
URL = "https://api.groq.com/openai/v1/chat/completions"
# Using llama-3.3-70b-versatile for high quality formatting and accuracy
MODEL = "llama-3.3-70b-versatile"

FILE_PATH = "/opt/lexilingo/scripts/categorized_words_final.json"

def needs_filling(entry):
    # Check example
    if not entry.get("example", "").strip():
        return True
    # Check phonetic
    p = entry.get("phonetic", "")
    if not p.strip() or "#N/A" in p or "N/A" in p:
        return True
        
    # Check translations
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
    prompt = """You are a top-tier linguistic AI. I will provide a JSON array of words. Some words are missing an 'example', a 'phonetic' transcription (IPA format), or specific 'translation' languages (en, vi, ja, ko, zh, fr, es). 
Your job is to return ONLY a JSON array containing objects for these words, filling in all missing components accurately.
Make sure:
1. `example`: Provide a clear, natural English sentence using the word.
2. `phonetic`: Provide the IPA transcription (e.g. /wɜːd/).
3. `translation`: Must contain keys 'en', 'vi', 'ja', 'ko', 'zh', 'fr', 'es'. Ensure 'vi' is 100% fluent Vietnamese, do not leave English words.

Return ONLY a JSON array of objects. Example output format:
[
  {
    "word": "apple",
    "example": "I ate a red apple.",
    "phonetic": "/ˈæp.əl/",
    "translation": {
      "en": "a round fruit",
      "vi": "quả táo",
      "ja": "りんご",
      "ko": "사과",
      "zh": "苹果",
      "fr": "pomme",
      "es": "manzana"
    }
  }
]
"""
    
    input_data = []
    for e in batch:
        input_data.append({
            "word": e.get('word', ''),
            "definition": e.get('definition', '')
        })
        
    user_content = json.dumps(input_data, ensure_ascii=False)

    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": prompt},
            {"role": "user", "content": user_content}
        ],
        "temperature": 0.1,
    }
    
    for attempt in range(5):
        try:
            api_key = get_next_key()
            headers = {
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json"
            }
            resp = requests.post(URL, headers=headers, json=payload)
            if resp.status_code == 200:
                try:
                    text = resp.json()['choices'][0]['message']['content']
                    text = clean_json_response(text)
                    return json.loads(text)
                except Exception as e:
                    print(f"JSON Parse error (Attempt {attempt+1}):", e)
                    time.sleep(2)
            elif resp.status_code == 429:
                print(f"Rate limited by Groq. Retrying... (Attempt {attempt+1})")
                time.sleep(5)
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

    missing_indices = [i for i, entry in enumerate(data) if needs_filling(entry)]
    print(f"Found {len(missing_indices)} words missing example, phonetic, or translation.")
    
    if not missing_indices:
        print("All words are fully populated!")
        sys.exit(0)

    # Groq handles up to ~8000 tokens output well, but let's use batch size 10 to guarantee valid JSON structure
    batch_size = 10
    total_batches = (len(missing_indices) + batch_size - 1) // batch_size

    for i in range(0, len(missing_indices), batch_size):
        batch_idxs = missing_indices[i:i+batch_size]
        batch = [data[idx] for idx in batch_idxs]

        print(f"Processing batch {i//batch_size + 1}/{total_batches} ({len(batch)} words)...")

        results = process_batch(batch)
        
        if not results:
            print("Failed to get results for this batch, skipping for now...")
            continue

        res_dict = {item.get('word', '').lower(): item for item in results if isinstance(item, dict)}

        updated_count = 0
        for idx in batch_idxs:
            w = data[idx].get('word', '').lower()
            if w in res_dict:
                new_data = res_dict[w]
                
                # Fill missing example
                if not data[idx].get('example', '').strip() and new_data.get('example', '').strip():
                    data[idx]['example'] = new_data['example'].strip()
                
                # Fill missing phonetic
                if not data[idx].get('phonetic', '').strip() or "#N/A" in data[idx].get('phonetic', ''):
                    if new_data.get('phonetic', '').strip():
                        data[idx]['phonetic'] = new_data['phonetic'].strip()
                
                # Fill missing translations
                if 'translation' not in data[idx]:
                    data[idx]['translation'] = {}
                
                new_trans = new_data.get('translation', {})
                for lang in ["en", "vi", "ja", "ko", "zh", "fr", "es"]:
                    val = new_trans.get(lang, "")
                    if lang not in data[idx]['translation'] or not str(data[idx]['translation'][lang]).strip() or "#N/A" in str(data[idx]['translation'][lang]):
                        if val and "#N/A" not in str(val):
                            data[idx]['translation'][lang] = val.strip()
                            
                updated_count += 1
                
        print(f"-> Successfully processed and filled {updated_count} words.")

        # Save constantly
        with open(FILE_PATH, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

        # Respect Groq rate limits
        time.sleep(1)

    print("Groq missing data backfill is complete!")

if __name__ == "__main__":
    main()
