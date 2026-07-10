import json
import asyncio
import aiohttp
import os
import re

INPUT_FILE = "/opt/lexilingo/scripts/all_extracted_words_with_media.json"
OUTPUT_FILE = "/opt/lexilingo/scripts/categorized_words_final.json"
GROQ_API_KEY = os.getenv("GROQ_API_KEY", "")
AI_URL = "https://api.groq.com/openai/v1/chat/completions"
BATCH_SIZE = 100

async def fetch_categorization(session, batch):
    words = [w['word'] for w in batch]
    prompt = f"""Categorize these English words into exactly ONE topic each.
Topics: business, technology, education, health, nature, daily_life, food, society, travel, arts, general.
Return ONLY valid JSON mapping string to string. Example: {{"apple": "food", "invest": "business"}}
Words: {json.dumps(words)}"""
    
    payload = {
        "model": "llama-3.3-70b-versatile",
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.1,
        "response_format": {"type": "json_object"}
    }
    headers = {"Authorization": f"Bearer {GROQ_API_KEY}"}
    
    try:
        async with session.post(AI_URL, json=payload, headers=headers, timeout=60) as resp:
            if resp.status == 200:
                data = await resp.json()
                content = data["choices"][0]["message"]["content"]
                content = content.strip()
                try:
                    return json.loads(content)
                except Exception:
                    pass
            else:
                print(f"Error {resp.status}: {await resp.text()}")
    except Exception as e:
        print(f"Error querying AI loop: {e}")
    return {}

async def main():
    if not os.path.exists(INPUT_FILE):
        print(f"Input file not found: {INPUT_FILE}")
        return

    with open(INPUT_FILE, "r", encoding="utf-8") as f:
        all_words = json.load(f)
    
    processed_dict = {}
    if os.path.exists(OUTPUT_FILE):
        with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
            try:
                processed = json.load(f)
                for w in processed:
                    processed_dict[w['word']] = w
            except:
                pass

    to_process = []
    for w in all_words:
        w_id = w['word']
        if w_id not in processed_dict or 'tags' not in processed_dict[w_id] or processed_dict[w_id]['tags'] == ["general"]:
            to_process.append(w)
        else:
            w['tags'] = processed_dict[w_id]['tags']
            processed_dict[w_id] = w
            
    print(f"Total words: {len(all_words)}")
    print(f"Words remaining to categorize: {len(to_process)}")

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
                    topic = topic.get("topic", "general")
                w['tags'] = [topic]
                processed_dict[w['word']] = w
            
            with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
                json.dump(list(processed_dict.values()), f, indent=2, ensure_ascii=False)
            
            await asyncio.sleep(1) # rate limit
                
    print(f"Done! Categorized data saved to {OUTPUT_FILE}")

if __name__ == "__main__":
    asyncio.run(main())
