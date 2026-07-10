import json
import asyncio
import aiohttp
import os
from collections import deque

INPUT_FILE = "/opt/lexilingo/scripts/categorized_words_final.json"
MAP_FILE = "/opt/lexilingo/scripts/phonetics_map.json"

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
BATCH_SIZE = 25

async def fetch_phonetics(session, words):
    prompt = f"""Provide ONLY the international phonetic alphabet (IPA) pronunciations string for each of these english words. Output MUST be ONLY a JSON object where keys are the words and values are the IPA string formatted like "/wɜːd/". Do not output anything else.
Format example:
{{
  "apple": "/ˈæpəl/",
  "banana": "/ˈbænənə/"
}}
Words: {json.dumps(words)}"""
    
    payload = {
        "model": "llama-3.1-8b-instant",
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.1,
        "response_format": {"type": "json_object"}
    }
    
    max_retries = 5
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
                    except Exception: return {}
                elif resp.status == 429:
                    await asyncio.sleep(5)
                else: return {}
        except Exception:
            await asyncio.sleep(3)
    return {}

async def main():
    if not os.path.exists(INPUT_FILE): return

    with open(INPUT_FILE, "r", encoding="utf-8") as f:
        all_words = json.load(f)
        
    if os.path.exists(MAP_FILE):
        with open(MAP_FILE, "r", encoding="utf-8") as f:
            phonetics_map = json.load(f)
    else:
        phonetics_map = {}
    
    to_process = []
    for w in all_words:
        word = w['word']
        old_phonetic = w.get("phonetic", "").strip()
        if word not in phonetics_map and not old_phonetic:
            to_process.append(word)

    print(f"Words needing phonetics: {len(to_process)}")

    async with aiohttp.ClientSession() as session:
        for i in range(0, len(to_process), BATCH_SIZE):
            batch = to_process[i:i+BATCH_SIZE]
            print(f"Batch {i//BATCH_SIZE + 1} / {(len(to_process)//BATCH_SIZE)+1}...")
            
            result = await fetch_phonetics(session, batch)
            
            if isinstance(result, dict):
                for word_str in batch:
                    if word_str in result:
                        phonetics_map[word_str] = result[word_str]
            
            with open(MAP_FILE, "w", encoding="utf-8") as f:
                json.dump(phonetics_map, f, indent=2, ensure_ascii=False)
            await asyncio.sleep(2)
            
    print("Completed!")

if __name__ == "__main__":
    asyncio.run(main())
