#!/bin/bash
set -e

cd /opt/lexilingo/backend-service

echo "1. Categorizing missing tags via Groq..."
./venv/bin/python3 /opt/lexilingo/scripts/re_categorize_groq.py

echo "2. Copying scripts and json to container..."
docker cp /opt/lexilingo/scripts/categorized_words_final.json lexilingo-backend-service:/app/categorized_words_final.json
docker cp /opt/lexilingo/backend-service/scripts/update_db_tags.py lexilingo-backend-service:/app/scripts/update_db_tags.py

echo "3. Updating Database tags..."
docker exec lexilingo-backend-service python3 /app/scripts/update_db_tags.py

echo "4. Checking results..."
grep -c '"general"' /opt/lexilingo/scripts/categorized_words_final.json || true

echo "ALL DONE!"
