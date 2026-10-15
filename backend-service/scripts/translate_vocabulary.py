import json
import urllib.request
import urllib.parse
import re
import time
import os

FILE_PATH = "/opt/lexilingo/backend-service/data/vocabulary_import.json"

def get_wiktionary_translations(word):
    url = f"https://en.wiktionary.org/w/api.php?action=query&prop=revisions&rvprop=content&rvslots=main&titles={urllib.parse.quote(word)}&format=json"
    req = urllib.request.Request(url, headers={'User-Agent': 'LexiLingo-VocabBot/1.0 (nhthang312@gmail.com)'})
    
    max_retries = 5
    base_delay = 5.0
    
    for attempt in range(max_retries):
        try:
            with urllib.request.urlopen(req) as response:
                data = json.loads(response.read().decode())
                pages = data.get('query', {}).get('pages', {})
                for page_id, page_info in pages.items():
                    if 'revisions' in page_info:
                        content = page_info['revisions'][0]['slots']['main']['*']
                        
                        translations = {}
                        for lang_code in ['ja', 'ko', 'zh', 'fr', 'es', 'vi']:
                            pattern = r'\{\{t[+ø-]?\|' + lang_code + r'\|([^}|]+)'
                            matches = re.findall(pattern, content)
                            if matches:
                                unique_matches = list(dict.fromkeys([m.strip() for m in matches]))
                                translations[lang_code] = ", ".join(unique_matches[:3])
                        return translations
                return {}
        except urllib.error.HTTPError as e:
            if e.code == 429:
                delay = base_delay * (2 ** attempt)
                print(f"Rate limited (429) for {word}. Retrying in {delay} seconds...")
                time.sleep(delay)
            else:
                print(f"HTTP Error fetching {word}: {e}")
                return {}
        except Exception as e:
            print(f"Error fetching {word}: {e}")
            return {}
            
    print(f"Failed to fetch {word} after {max_retries} retries.")
    return {}

def main():
    print("Loading vocabulary...")
    with open(FILE_PATH, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    count = 0
    updated = 0
    
    print(f"Translating all words and overwriting existing translations...")
    
    for item in data:
        word = item.get("word")
        if not word:
            continue
            
        print(f"[{count+1}] Fetching translations for: {word}")
            
        new_trans = get_wiktionary_translations(word)
        if new_trans:
            # Overwrite existing translations with Wiktionary ones
            translation = item.get("translation", {})
            for lang, text in new_trans.items():
                if text: # only if we found a translation
                    translation[lang] = text
                    updated += 1
            item['translation'] = translation
        
        time.sleep(2.0) # Sleep 2 seconds to respect Wiktionary API rate limits
        count += 1

        
        # Save every 50 items to avoid losing data on crash
        if count % 50 == 0 and updated > 0:
            print(f"Checkpoint: Saving {updated} new translations...")
            with open(FILE_PATH, 'w', encoding='utf-8') as f:
                json.dump(data, f, ensure_ascii=False, indent=2)

    if updated > 0:
        print(f"Saving {updated} new translations...")
        with open(FILE_PATH, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        print("Save completed.")
    else:
        print("No updates needed for the scanned words.")

if __name__ == "__main__":
    main()
