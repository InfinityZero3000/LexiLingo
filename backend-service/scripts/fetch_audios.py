import json
import os
import urllib.request
import urllib.parse
import urllib.error
import ssl
import time
import re

JSON_PATH = "/opt/lexilingo/backend-service/data/vocabulary_import.json"
MEDIA_DIR = "/opt/lexilingo/backend-service/data/media"

def clean_filename(word):
    # Remove any character that is not alphanumeric or underscore/dash
    cleaned = re.sub(r"[^\w\-_]", "", word)
    return cleaned.lower()

def download_audio_from_url(url, dest_path):
    if url.startswith("//"):
        url = "https:" + url
        
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    }
    req = urllib.request.Request(url, headers=headers)
    
    max_retries = 3
    base_delay = 2.0
    
    for attempt in range(max_retries):
        try:
            context = ssl._create_unverified_context()
            with urllib.request.urlopen(req, context=context) as response:
                with open(dest_path, "wb") as f:
                    f.write(response.read())
            return True
        except urllib.error.HTTPError as e:
            if e.code == 429:
                delay = base_delay * (2 ** attempt)
                print(f"Rate limited (429) downloading audio. Retrying in {delay} seconds...")
                time.sleep(delay)
            else:
                print(f"HTTP error downloading audio from {url}: {e.code}")
                return False
        except Exception as e:
            print(f"Error downloading audio from {url}: {e}")
            time.sleep(1.0)
            
    return False

def get_audio_url_from_api(word):
    url = f"https://api.dictionaryapi.dev/api/v2/entries/en/{urllib.parse.quote(word)}"
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    }
    req = urllib.request.Request(url, headers=headers)
    
    try:
        context = ssl._create_unverified_context()
        with urllib.request.urlopen(req, context=context) as response:
            data = json.loads(response.read().decode("utf-8"))
            if data and isinstance(data, list):
                # Search for any valid audio link in phonetics
                phonetics = data[0].get("phonetics", [])
                # First try finding US audio, then any audio
                for p in phonetics:
                    audio_url = p.get("audio")
                    if audio_url and ("-us" in audio_url or "us.mp3" in audio_url):
                        return audio_url
                for p in phonetics:
                    audio_url = p.get("audio")
                    if audio_url:
                        return audio_url
    except urllib.error.HTTPError as e:
        if e.code == 404:
            # Word not found
            return None
        print(f"API HTTP Error {e.code} for word '{word}'")
    except Exception as e:
        print(f"API Error fetching word '{word}': {e}")
        
    return None

def main():
    if not os.path.exists(MEDIA_DIR):
        os.makedirs(MEDIA_DIR, exist_ok=True)
        print(f"Created media directory: {MEDIA_DIR}")
        
    print("Loading vocabulary JSON...")
    with open(JSON_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)
        
    # Count missing audios
    to_download = []
    for idx, item in enumerate(data):
        word = item.get("word")
        if not word:
            continue
            
        audios = item.get("audios", {})
        pronunciation_file = None
        if isinstance(audios, dict):
            pronunciation_file = audios.get("pronunciation")
        elif isinstance(audios, list) and audios:
            pronunciation_file = audios[0]
            
        audio_path = os.path.join(MEDIA_DIR, pronunciation_file) if pronunciation_file else None
        
        # If pronunciation is not configured, or file does not exist on disk
        if not pronunciation_file or not os.path.exists(audio_path):
            to_download.append(idx)
            
    print(f"Total items in JSON: {len(data)}")
    print(f"Total items needing audio download: {len(to_download)}")
    
    if not to_download:
        print("All vocabulary audio files are already present on disk!")
        return
        
    downloaded_count = 0
    failed_count = 0
    
    # We will only attempt to fetch up to a reasonable number to avoid hitting API limits
    # e.g., 200 items in a single run. Let's make it configurable or fetch them.
    # Since this is /goal, we can let it run to process all of them, but we will print progress.
    # For DictionaryAPI.dev, there are no strict keys, but rate limits may apply. 
    # We will sleep 0.5s between requests.
    
    for count, idx in enumerate(to_download):
        item = data[idx]
        word = item.get("word")
        
        print(f"[{count+1}/{len(to_download)}] Fetching audio for '{word}'...")
        audio_url = get_audio_url_from_api(word)
        
        if audio_url:
            # Determine extension
            ext = ".mp3"
            if ".wav" in audio_url.lower():
                ext = ".wav"
                
            filename = f"{clean_filename(word)}{ext}"
            dest_path = os.path.join(MEDIA_DIR, filename)
            
            print(f"  Downloading from: {audio_url}")
            success = download_audio_from_url(audio_url, dest_path)
            
            if success:
                item["audios"] = {"pronunciation": filename}
                downloaded_count += 1
                print(f"  Successfully saved audio as '{filename}'")
                
                # Checkpoint save
                if downloaded_count % 10 == 0:
                    with open(JSON_PATH, "w", encoding="utf-8") as f:
                        json.dump(data, f, ensure_ascii=False, indent=2)
                    print("  Progress checkpoint saved.")
            else:
                failed_count += 1
                print(f"  Failed to download audio file.")
        else:
            failed_count += 1
            print(f"  No audio URL found in dictionary API.")
            
        time.sleep(0.5) # respectful delay
        
    # Final save
    if downloaded_count > 0:
        with open(JSON_PATH, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        print("Final updates saved.")
        
    print(f"Completed audio download task. Successes: {downloaded_count}, Failures/Not Found: {failed_count}")

if __name__ == "__main__":
    main()
