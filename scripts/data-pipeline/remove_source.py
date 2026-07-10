import json

INPUT_FILE = "/opt/lexilingo/scripts/categorized_words_final.json"

def main():
    print("Loading JSON...")
    with open(INPUT_FILE, "r", encoding="utf-8") as f:
        data = json.load(f)
    
    count = 0
    for item in data:
        if "source" in item:
            del item["source"]
            count += 1
            
    print(f"Removed 'source' field from {count} items.")
    
    print("Saving JSON...")
    with open(INPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    
    print("Done!")

if __name__ == "__main__":
    main()
