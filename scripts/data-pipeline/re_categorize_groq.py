import json
import asyncio
import aiohttp
import os

INPUT_FILE = "/opt/lexilingo/scripts/categorized_words_final.json"
OUTPUT_FILE = "/opt/lexilingo/scripts/categorized_words_final.json"
GROQ_API_KEY = os.getenv("GROQ_API_KEY", "")
AI_URL = "https://api.groq.com/openai/v1/chat/completions"
BATCH_SIZE = 50  # Reduced batch size to stay under token limits better

async def fetch_categorization(session, batch):
    words = [w['word'] for w in batch]
    prompt = f"""Categorize these English words into exactly ONE topic each.
Topics: business, technology, education, health, nature, daily_life, food, society, travel, arts, sports, science, general.
Return ONLY valid JSON with keys as words and values as topics. Example: {{"apple": "food", "invest": "business"}}

Words: {json.dumps(words)}"""
    
    payload = {
        "model": "llama-3.1-8b-instant",
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.1,
        "response_format": {"type": "json_object"}
    }
    headers = {"Authorization": f"Bearer {GROQ_API_KEY}"}
    
    max_retries = 5
    for attempt in range(max_retries):
        try:
            async with session.post(AI_URL, json=payload, headers=headers, timeout=60) as resp:
                if resp.status == 200:
                    data = await resp.json()
                    content = data["choices"][0]["message"]["content"].strip()
                    try:
                        return json.loads(content)
                    except Exception as e:
                        print("JSON Parse Error:", e)
                        return {}
                elif resp.status == 429:
                    error_text = await resp.text()
                    print(f"Rate limited. Waiting 5s... ({error_text})")
                    await asyncio.sleep(5)
                else:
                    print(f"Error {resp.status}: {await resp.text()}")
                    return {}
        except Exception as e:
            print(f"Network/Request Error: {e}")
            await asyncio.sleep(5)
    return {}

async def main():
    if not os.path.exists(INPUT_FILE):
        print(f"Input file not found: {INPUT_FILE}")
        return

    with open(INPUT_FILE, "r", encoding="utf-8") as f:
        all_words = json.load(f)
    
    to_process = []
    for w in all_words:
        if w.get('tags', []) == ["general"] or not w.get('tags'):
            to_process.append(w)
            
    print(f"Total words: {len(all_words)}")
    print(f"Words to categorize: {len(to_process)}")

    if len(to_process) == 0:
        print("All done!")
        return

    async with aiohttp.ClientSession() as session:
        for i in range(0, len(to_process), BATCH_SIZE):
            batch = to_process[i:i+BATCH_SIZE]
            print(f"Processing batch {i//BATCH_SIZE + 1} / {(len(to_process)//BATCH_SIZE)+1}...")
            
            cat_map = await fetch_categorization(session, batch)
            
            for w in batch:
                topic = "general"
                if isinstance(cat_map, dict):
                    topic = cat_map.get(w['word'], "general")
                if isinstance(topic, dict):
                    topic = topic.get("category", "general")
                
                # Make sure we don't accidentally blank out if the model failed
                if topic is not None and isinstance(topic, str):
                    w['tags'] = [topic.lower()]
            
            with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
                json.dump(all_words, f, indent=2, ensure_ascii=False)
            
            # Rate limit protection (30 requests per minute = 1 request per 2 seconds max)
            # 12,000 TPM limit vs token consumption means we might still need to wait.
            await asyncio.sleep(3)
                
    print(f"Done! Categorized data saved")

if __name__ == "__main__":
    asyncio.run(main())
