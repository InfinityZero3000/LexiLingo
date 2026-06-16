import json
import urllib.request
import urllib.parse
import urllib.error
import ssl
import time
import os
import re

FILE_PATH = "/opt/lexilingo/backend-service/data/vocabulary_import.json"

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

def clean_definition(text):
    # Remove leading/trailing whitespace and quotes
    text = text.strip()
    # Remove surrounding double quotes if present
    if text.startswith('"') and text.endswith('"'):
        text = text[1:-1].strip()
    if text.startswith("'") and text.endswith("'"):
        text = text[1:-1].strip()
    
    # Remove common prefixes from LLM output
    prefixes = [
        "definition:", "definition is:", "the definition is:", "refers to:", 
        "meaning:", "a definition of", "frankly means"
    ]
    lower_text = text.lower()
    for prefix in prefixes:
        if lower_text.startswith(prefix):
            text = text[len(prefix):].strip()
            # Clean again in case of leading punctuation or quotes
            if text.startswith(':') or text.startswith('-'):
                text = text[1:].strip()
            if text.startswith('"') and text.endswith('"'):
                text = text[1:-1].strip()
            break
            
    # Capitalize the first letter and ensure it ends with a period if it is a complete sentence/phrase
    if text:
        text = text[0].upper() + text[1:]
        if not text.endswith('.') and not text.endswith('!') and not text.endswith('?'):
            text += '.'
            
    return text

def get_groq_definition(word, example, translation_en, translation_vi, tags):
    url = "https://api.groq.com/openai/v1/chat/completions"
    
    prompt = f"Word: {word}\n"
    if example:
        prompt += f"Example Sentence: {example}\n"
    if translation_en:
        prompt += f"English Translation/Synonym: {translation_en}\n"
    if translation_vi:
        prompt += f"Vietnamese Translation: {translation_vi}\n"
    if tags:
        prompt += f"Category/Tags: {tags}\n"
        
    system_msg = (
        "You are an expert lexicographer writing definitions for language learners. "
        "Provide a clear, concise definition of the requested word in English. "
        "The definition must be suitable for intermediate language learners and match the meaning of the word as used in the given example sentence and translations.\n"
        "Rules:\n"
        "1. Output ONLY the definition itself (e.g. 'In a straightforward, honest, and direct manner').\n"
        "2. Do NOT include the word being defined, do NOT include quotes, do NOT include any introductory or explanatory text (e.g. do not say 'Here is the definition' or 'Definition:').\n"
        "3. Keep it to one concise sentence or phrase."
    )
    
    payload = {
        "model": "llama-3.3-70b-versatile",
        "messages": [
            {"role": "system", "content": system_msg},
            {"role": "user", "content": prompt}
        ],
        "temperature": 0.0,
        "max_tokens": 150
    }
    
    max_retries = 3
    base_delay = 2.0
    
    for attempt in range(len(API_KEYS) * 2): # Try rotating keys up to 2 full cycles
        api_key = get_next_api_key()
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }
        req = urllib.request.Request(url, data=json.dumps(payload).encode("utf-8"), headers=headers, method="POST")
        
        try:
            context = ssl._create_unverified_context()
            with urllib.request.urlopen(req, context=context) as response:
                res_data = json.loads(response.read().decode("utf-8"))
                raw_content = res_data["choices"][0]["message"]["content"]
                return clean_definition(raw_content)
        except urllib.error.HTTPError as e:
            # Read error body if possible
            try:
                err_body = e.read().decode("utf-8")
            except Exception:
                err_body = ""
            print(f"API key index {current_key_index-1} failed with HTTP {e.code} for word '{word}'. Error: {err_body[:200]}")
            
            # If rate limit or other error, try the next key immediately
            time.sleep(0.5)
        except Exception as e:
            print(f"API key index {current_key_index-1} failed with generic error for word '{word}': {e}")
            time.sleep(0.5)
            
    # If all keys failed, wait and retry with exponential backoff
    print("All API keys failed. Waiting 5 seconds before retrying...")
    time.sleep(5.0)
    return ""

def main():
    print("Loading vocabulary JSON...")
    with open(FILE_PATH, 'r', encoding='utf-8') as f:
        data = json.load(f)
        
    print(f"Total vocabulary items: {len(data)}")
    
    # Identify items to fill
    to_fill = []
    for idx, item in enumerate(data):
        definition = item.get("definition", "")
        if definition == "#N/A yet" or not definition:
            to_fill.append(idx)
            
    print(f"Found {len(to_fill)} items needing definition updates.")
    
    if not to_fill:
        print("No items to fill!")
        return
        
    success_count = 0
    
    for count, idx in enumerate(to_fill):
        item = data[idx]
        word = item.get("word")
        example = item.get("example", "")
        phonetic = item.get("phonetic", "")
        tags = item.get("tags", "")
        translation_block = item.get("translation", {})
        translation_en = translation_block.get("en", "")
        translation_vi = translation_block.get("vi", "")
        
        print(f"[{count+1}/{len(to_fill)}] Fetching definition for '{word}'...")
        
        definition = get_groq_definition(word, example, translation_en, translation_vi, tags)
        
        if definition:
            print(f"  Word: '{word}'")
            print(f"  Definition: {definition}")
            item["definition"] = definition
            success_count += 1
            
            # Save progressively
            with open(FILE_PATH, 'w', encoding='utf-8') as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            print("  Progress saved.")
        else:
            print(f"  Warning: Failed to fetch definition for '{word}' after trying all API keys.")
            
        # Small delay between requests to be polite
        time.sleep(0.5)
        
    print(f"Processing complete. Filled {success_count}/{len(to_fill)} missing definitions.")

if __name__ == "__main__":
    main()
