#!/bin/bash
# Script wrapper to download models with virtual environment

# Change to backend directory
cd "$(dirname "$0")"

# Activate virtual environment
if [ -f ".venv/bin/activate" ]; then
    echo "🔄 Activating virtual environment..."
    source .venv/bin/activate
else
    echo "❌ Virtual environment not found. Please run: python3 -m venv .venv"
    exit 1
fi

# Set OpenMP workaround for macOS
export KMP_DUPLICATE_LIB_OK=TRUE

# Run download script
echo "🚀 Starting model download..."
python scripts/download_models.py

# Deactivate venv
deactivate
