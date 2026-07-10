#!/bin/bash
set -e
cd /opt/lexilingo/backend-service

echo "1. Copying updated JSON and script into docker..."
docker cp /opt/lexilingo/scripts/categorized_words_final.json lexilingo-backend-service:/app/categorized_words_final.json
docker cp /opt/lexilingo/scripts/update_db_phonetics.py lexilingo-backend-service:/app/scripts/update_db_phonetics.py

echo "2. Applying Phonetics to Postgres..."
docker exec lexilingo-backend-service python3 /app/scripts/update_db_phonetics.py

echo "ALL DONE!"
