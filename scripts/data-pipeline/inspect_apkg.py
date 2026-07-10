import zipfile
import sqlite3
import os
import glob
import tempfile
import json

base_dir = "/opt/lexilingo/scripts"
apkg_files = glob.glob(os.path.join(base_dir, "*.apkg"))
extract_root = os.path.join(base_dir, "apkg_extracted")
os.makedirs(extract_root, exist_ok=True)

for apkg_file in apkg_files:
    print(f"\n{'='*50}\nInspecting: {os.path.basename(apkg_file)}\n{'='*50}")
    extract_dir = os.path.join(
        extract_root,
        os.path.splitext(os.path.basename(apkg_file))[0],
    )
    os.makedirs(extract_dir, exist_ok=True)

    if os.listdir(extract_dir):
        print(f"Already extracted: {extract_dir}")
    else:
        try:
            with zipfile.ZipFile(apkg_file, 'r') as zip_ref:
                zip_ref.extractall(extract_dir)
            print(f"Extracted to: {extract_dir}")
        except Exception as e:
            print(f"Failed to extract: {e}")
            continue

    # Prefer collection.anki21 (newer format), fall back to collection.anki2
    anki21_path = os.path.join(extract_dir, "collection.anki21")
    anki2_path = os.path.join(extract_dir, "collection.anki2")
    if os.path.exists(anki21_path):
        db_path = anki21_path
        print(f"Using collection.anki21 ({os.path.getsize(anki21_path)} bytes)")
    elif os.path.exists(anki2_path):
        db_path = anki2_path
        print(f"Using collection.anki2 ({os.path.getsize(anki2_path)} bytes)")
    else:
        print("No collection.anki2 or .anki21 found in archive")
        continue

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Get models (to understand fields)
    cursor.execute("SELECT models FROM col LIMIT 1")
    models_json = cursor.fetchone()[0]
    models = json.loads(models_json)

    print("Models (Note Types) found:")
    for model_id, model in models.items():
        field_names = [f['name'] for f in model['flds']]
        print(f"  - {model['name']}: {field_names}")

    # Get a sample note
    cursor.execute("SELECT flds FROM notes LIMIT 1")
    sample_note = cursor.fetchone()
    if sample_note:
        fields = sample_note[0].split('\x1f')
        print("\nSample Note Fields:")
        for i, val in enumerate(fields):
            clean_val = val.replace('\n', ' ')[:100]
            if len(val) > 100:
                clean_val += "..."
            print(f"  [{i}]: {clean_val}")
    else:
        print("No notes found.")

    conn.close()
