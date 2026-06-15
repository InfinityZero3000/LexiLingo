import json
import urllib.request
import urllib.parse
import re

def get_wiktionary_translations(word):
    url = f"https://en.wiktionary.org/w/api.php?action=query&prop=revisions&rvprop=content&rvslots=main&titles={urllib.parse.quote(word)}&format=json"
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    try:
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode())
            pages = data.get('query', {}).get('pages', {})
            for page_id, page_info in pages.items():
                if 'revisions' in page_info:
                    content = page_info['revisions'][0]['slots']['main']['*']
                    
                    # Look for translation tags like {{t|vi|quả táo}} or {{t+|fr|pomme}}
                    # The format is typically {{t[+-ø]?|lang_code|word|...}}
                    translations = {}
                    for lang_code in ['ja', 'ko', 'zh', 'fr', 'es', 'vi']:
                        # Regex to match the translation macro
                        pattern = rf'\{\{t[+ø-]?\|{lang_code}\|([^}}|]+)'
                        matches = re.findall(pattern, content)
                        if matches:
                            # Clean up and get unique translations
                            unique_matches = list(dict.fromkeys([m.strip() for m in matches]))
                            translations[lang_code] = ", ".join(unique_matches[:3])
                    return translations
            return {}
    except Exception as e:
        print(f"Error: {e}")
        return {}

if __name__ == "__main__":
    print(get_wiktionary_translations("apple"))
