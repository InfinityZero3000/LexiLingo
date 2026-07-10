import json
import asyncio
import aiohttp
import os
from collections import deque

INPUT_FILE = "/opt/lexilingo/scripts/categorized_words_final.json"
MAP_FILE = "/opt/lexilingo/scripts/translations_map.json"

# Get API keys from environment variable (comma-separated), fallback to empty list
api_keys_env = os.getenv("GROQ_API_KEYS", "")
API_KEYS = [k.strip() for k in api_keys_env.split(",") if k.strip()]
if not API_KEYS:
    single_key = os.getenv("GROQ_API_KEY", "")
    if single_key:
        API_KEYS = [single_key]
    else:
        API_KEYS = []

key_queue = deque(API_KEYS)

AI_URL = "https://api.groq.com/openai/v1/chat/completions"
BATCH_SIZE = 15

async def fetch_translations(session, batch):
    words = [w['word'] for w in batch]
    prompt = f"""You are a helpful dictionary translator. Translate these English words into 7 languages: English (definition), Vietnamese (vi), Japanese (ja), Korean (ko), Simplified Chinese (zh), French (fr), Spanish (es).
Return ONLY a valid JSON object where keys are the English words, and values are objects containing the ISO language codes as keys.
Format example:
{{
  "apple": {{
    "en": "a round fruit with red or green skin",
    "vi": "quả táo",
    "ja": "りんご",
    "ko": "사과",
    "zh": "苹果",
    "fr": "pomme",
    "es": "manzana"
  }}
}}

Words to translate: {json.dumps(words)}"""
    
    payload = {
        "model": "llama-3.1-8b-instant",
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.1,
        "response_format": {"type": "json_object"}
    }
    
    max_retries = 10
    for attempt in range(max_retries):
        current_key = key_queue[0]
        key_queue.rotate(-1)
        headers = {"Authorization": f"Bearer {current_key}"}
        try:
            async with session.post(AI_URL, json=payload, headers=headers, timeout=60) as resp:
                if resp.status == 200:
                    data = await resp.json()
                    content = data["choices"][0]["message"]["content"].strip()
                    try:
                        return json.loads(content)
                    except Exception as e:
                        return {}
                elif resp.status == 429:
                    await asyncio.sleep(5)
                else:
                    return {}
        except Exception as e:
            await asyncio.sleep(3)
    return {}

async def main():
    if not os.path.exists(INPUT_FILE):
        return

    with open(INPUT_FILE, "r", encoding="utf-8") as f:
        all_words = json.load(f)
        
    if os.path.exists(MAP_FILE):
        with open(MAP_FILE, "r", encoding="utf-8") as f:
            translations_map = json.load(f)
    else:
        translations_map = {}
    
    to_process = []
    for w in all_words:
        word = w['word']
        if word not in translations_map:
            to_process.append(w)

    print(f"Words needing translation: {len(to_process)}")

    async with aiohttp.ClientSession() as session:
        for i in range(0, len(to_process), BATCH_SIZE):
            batch = to_process[i:i+BATCH_SIZE]
            print(f"Batch {i//BATCH_SIZE + 1} / {(len(to_process)//BATCH_SIZE)+1}...")
            
            result = await fetch_translations(session, batch)
            
            for w in batch:
                word_str = w['word']
                if isinstance(result, dict) and word_str in result:
                    trans_data = result[word_str]
                    if isinstance(trans_data, dict):
                        translations_map[word_str] = trans_data
            
            with open(MAP_FILE, "w", encoding="utf-8") as f:
                json.dump(translations_map, f, indent=2, ensure_ascii=False)
            await asyncio.sleep(2)

    print("Completed!")

if __name__ == "__main__":
    asyncio.run(main())
