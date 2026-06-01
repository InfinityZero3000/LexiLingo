import json
import os
from pathlib import Path

def manage_i18n_key(key_path: str, english_text: str) -> dict:
    \"\"\"
    Add or update an i18n key across all 7 language files.
    
    Args:
        key_path: The dot-separated path for the key (e.g., 'auth.login.title')
        english_text: The English text to add
    \"\"\"
    base_dir = Path(__file__).parent.parent.parent / "flutter-app" / "assets" / "i18n"
    languages = ["en", "vi", "ja", "ko", "zh", "fr", "es"]
    results = {}
    
    if not base_dir.exists():
        return {"error": f"i18n directory not found at {base_dir}"}
        
    for lang in languages:
        file_path = base_dir / f"{lang}.json"
        
        # Initialize if doesn't exist
        if not file_path.exists():
            data = {}
        else:
            try:
                with open(file_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
            except json.JSONDecodeError:
                data = {}
                
        # Split key path to update nested dict
        keys = key_path.split('.')
        current = data
        for i, k in enumerate(keys[:-1]):
            if k not in current or not isinstance(current[k], dict):
                current[k] = {}
            current = current[k]
            
        # Add the string (use English as placeholder for other languages if they don't have it)
        # If it's already there and not English, keep the translation unless it's English file
        final_key = keys[-1]
        
        if lang == "en":
            current[final_key] = english_text
            results[lang] = "updated"
        else:
            if final_key not in current:
                current[final_key] = english_text  # Set fallback to English
                results[lang] = "added_fallback"
            else:
                results[lang] = "kept_existing"
                
        # Write back
        with open(file_path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            
    return {
        "success": True,
        "message": f"Updated key '{key_path}'",
        "details": results
    }
