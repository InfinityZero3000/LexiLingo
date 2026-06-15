#!/bin/bash
# run_tasks.sh
# Coordindates the vocabulary audio downloading and vocabulary database expansion.

set -e

SCRIPT_DIR="/opt/lexilingo/backend-service/scripts"
LOG_DIR="/opt/lexilingo/backend-service/logs"

mkdir -p "$LOG_DIR"

echo "=== STARTING VOCABULARY AND AUDIO TASKS ==="
echo "Logs will be stored in $LOG_DIR"

# Task 1: Fetch audios for existing words
echo ""
echo "[Task 1/2] Fetching and downloading missing audios for existing vocabulary..."
python3 -u "$SCRIPT_DIR/fetch_audios.py" 2>&1 | tee "$LOG_DIR/fetch_audios.log"

# Task 2: Expand vocabulary with CEFR and IELTS levels
echo ""
echo "[Task 2/2] Expanding vocabulary JSON with CEFR and IELTS words using Groq API..."
python3 -u "$SCRIPT_DIR/expand_vocabulary.py" 2>&1 | tee "$LOG_DIR/expand_vocabulary.log"

echo ""
echo "=== ALL TASKS COMPLETED SUCCESSFULLY ==="
