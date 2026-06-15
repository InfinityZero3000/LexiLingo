import json
import urllib.request
import urllib.parse
import re
import time

FILE_PATH = "/opt/lexilingo/backend-service/data/vocabulary_import.json"

def strip_html(text):
    # Remove HTML tags
    clean = re.compile('<.*?>')
    return re.sub(clean, '', text)

def get_wiktionary_definition(word):
    url = f"https://en.wiktionary.org/api/rest_v1/page/definition/{urllib.parse.quote(word)}"
    req = urllib.request.Request(url, headers={
        'User-Agent': 'LexiLingo-VocabBot/1.0 (contact@lexilingo.com)',
        'Accept': 'application/json'
    })
    
    max_retries = 5
    base_delay = 5.0
    
    for attempt in range(max_retries):
        try:
            with urllib.request.urlopen(req) as response:
                data = json.loads(response.read().decode())
                
                # data format: {"en": [{"partOfSpeech": "Noun", "definitions": [{"definition": "..."}]}]}
                if "en" in data and len(data["en"]) > 0:
                    for pos_block in data["en"]:
                        if "definitions" in pos_block and len(pos_block["definitions"]) > 0:
                            # get the very first definition string
                            raw_def = pos_block["definitions"][0].get("definition", "")
                            if raw_def:
                                return strip_html(raw_def)
                return ""
        except urllib.error.HTTPError as e:
            if e.code == 429:
                delay = base_delay * (2 ** attempt)
                print(f"Rate limited (429) for {word}. Retrying in {delay} seconds...")
                time.sleep(delay)
            elif e.code == 404:
                # Word not found on wiktionary
                return ""
            else:
                print(f"HTTP Error fetching {word}: {e}")
                return ""
        except Exception as e:
            print(f"Error fetching {word}: {e}")
            return ""
            
    print(f"Failed to fetch {word} after {max_retries} retries.")
    return ""

def main():
    print("Loading vocabulary...")
    with open(FILE_PATH, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    count = 0
    updated = 0
    
    print(f"Fetching missing definitions...")
    
    for item in data:
        word = item.get("word")
        definition = item.get("definition", "")
        
        if not word:
            continue
            
        if definition == "#N/A yet" or definition == "":
            print(f"[{count+1}] Fetching definition for: {word}")
            
            new_def = get_wiktionary_definition(word)
            if new_def:
                item['definition'] = new_def
                updated += 1
            
            time.sleep(2.0) # Polite delay
        
        count += 1
        
        # Checkpoint save
        if count % 500 == 0 and updated > 0:
            print(f"Checkpoint: Saving {updated} new definitions...")
            with open(FILE_PATH, 'w', encoding='utf-8') as f:
                json.dump(data, f, ensure_ascii=False, indent=2)

    if updated > 0:
        print(f"Saving {updated} final definitions...")
        with open(FILE_PATH, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        print("Save completed.")
    else:
        print("No new definitions were updated.")

if __name__ == "__main__":
    main()
