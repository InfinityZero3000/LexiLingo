#!/usr/bin/env python3
"""
Download and setup all AI models for LexiLingo Backend

Models to download:
1. STT: Faster-Whisper (openai/whisper-small)
2. Context Encoder: sentence-transformers/all-MiniLM-L6-v2
3. Pronunciation: facebook/hubert-large-ls960-ft
4. TTS: Piper voices (en_US-lessac-medium)
5. Vietnamese: vilm/vinallama-7b-chat (optional, lazy load)
"""

import os
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

def download_whisper():
    """Download Faster-Whisper model"""
    print("\n" + "="*60)
    print(" Downloading Faster-Whisper (large-v3)...")
    print("="*60)
    
    try:
        from faster_whisper import WhisperModel
        
        model = WhisperModel(
            "large-v3",
            device="cpu",
            compute_type="int8",
            download_root="./models/whisper"
        )
        print(" Faster-Whisper downloaded successfully!")
        return True
    except Exception as e:
        print(f" Failed to download Faster-Whisper: {e}")
        return False


def download_sentence_transformers():
    """Download sentence-transformers embedding model"""
    print("\n" + "="*60)
    print(" Downloading all-MiniLM-L6-v2 embeddings...")
    print("="*60)
    
    try:
        from sentence_transformers import SentenceTransformer
        
        model = SentenceTransformer(
            "sentence-transformers/all-MiniLM-L6-v2",
            cache_folder="./models/embeddings"
        )
        print(" Sentence-Transformers downloaded successfully!")
        return True
    except Exception as e:
        print(f" Failed to download Sentence-Transformers: {e}")
        return False


def download_hubert():
    """Download HuBERT model for pronunciation analysis"""
    print("\n" + "="*60)
    print(" Downloading HuBERT (facebook/hubert-large-ls960-ft)...")
    print(" Using safetensors format for security")
    print("="*60)
    
    try:
        from transformers import HubertForCTC, Wav2Vec2Processor
        
        model_name = "facebook/hubert-large-ls960-ft"
        cache_dir = "./models/hubert"
        
        # Download processor
        processor = Wav2Vec2Processor.from_pretrained(
            model_name,
            cache_dir=cache_dir
        )
        
        # Download model with safetensors (bypass torch security issue)
        print("   Downloading model weights...")
        model = HubertForCTC.from_pretrained(
            model_name,
            cache_dir=cache_dir,
            use_safetensors=True  # Use safetensors instead of pytorch_model.bin
        )
        print(" HuBERT downloaded successfully!")
        return True
    except Exception as e:
        print(f" Failed to download HuBERT: {e}")
        print(" Tip: HuBERT requires safetensors format or torch>=2.6")
        return False


def download_piper_voice():
    """Download Piper TTS voice"""
    print("\n" + "="*60)
    print(" Downloading Piper TTS voice (en_US-lessac-medium)...")
    print("="*60)
    
    try:
        import requests
        from pathlib import Path
        
        # Create models directory
        tts_dir = Path("./models/piper")
        tts_dir.mkdir(parents=True, exist_ok=True)
        
        voice_name = "en_US-lessac-medium"
        base_url = "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/lessac/medium"
        
        files = [
            "en_US-lessac-medium.onnx",
            "en_US-lessac-medium.onnx.json",
        ]
        
        for file in files:
            file_path = tts_dir / file
            if file_path.exists():
                print(f"   {file} already exists, skipping...")
                continue
                
            url = f"{base_url}/{file}"
            print(f"   Downloading {file}...")
            
            response = requests.get(url, stream=True)
            response.raise_for_status()
            
            with open(file_path, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    f.write(chunk)
            
            print(f"   Downloaded {file}")
        
        print(" Piper TTS voice downloaded successfully!")
        print(f"   Model path: {tts_dir / f'{voice_name}.onnx'}")
        return True
    except Exception as e:
        print(f" Failed to download Piper voice: {e}")
        return False


def download_vietnamese_model():
    """Download Vietnamese LLaMA model (optional)"""
    print("\n" + "="*60)
    print(" Downloading Vietnamese LLaMA (vilm/vinallama-7b-chat)...")
    print("️  WARNING: This is a large model (8GB+), skipping by default")
    print("   To download, set DOWNLOAD_VIETNAMESE=1 environment variable")
    print("="*60)
    
    if os.getenv("DOWNLOAD_VIETNAMESE", "0") != "1":
        print("⏭️  Skipped Vietnamese model download")
        return True
    
    try:
        from transformers import AutoTokenizer, AutoModelForCausalLM
        
        model_name = "vilm/vinallama-7b-chat"
        cache_dir = "./models/llama"
        
        print("   Downloading tokenizer...")
        tokenizer = AutoTokenizer.from_pretrained(
            model_name,
            cache_dir=cache_dir
        )
        
        print("   Downloading model (this will take a while)...")
        model = AutoModelForCausalLM.from_pretrained(
            model_name,
            cache_dir=cache_dir,
            load_in_8bit=True,  # Use 8-bit quantization to save memory
            device_map="auto"
        )
        
        print(" Vietnamese LLaMA downloaded successfully!")
        return True
    except Exception as e:
        print(f" Failed to download Vietnamese model: {e}")
        return False


def create_env_file():
    """Create .env file with model configurations"""
    print("\n" + "="*60)
    print(" Creating .env configuration file...")
    print("="*60)
    
    env_path = Path(__file__).parent.parent / ".env"
    
    if env_path.exists():
        print("️  .env file already exists. Please update manually.")
        return True
    
    env_content = """# LexiLingo Backend Configuration
# Generated by download_models.py

# ============================================================
# Model Configurations
# ============================================================

# STT: Faster-Whisper
STT_MODEL_NAME=large-v3
STT_DEVICE=cpu
STT_COMPUTE_TYPE=int8
STT_BEAM_SIZE=5
STT_VAD=true
STT_LANGUAGE=en

# TTS: Piper
TTS_MODEL_PATH=./models/piper/en_US-lessac-medium.onnx
TTS_CONFIG_PATH=./models/piper/en_US-lessac-medium.onnx.json
TTS_SPEAKER_ID=0
TTS_VOICE=en_US-lessac-medium

# Embeddings: Sentence-Transformers
EMBEDDING_MODEL=sentence-transformers/all-MiniLM-L6-v2
EMBEDDING_DEVICE=cpu

# HuBERT: Pronunciation Analysis
HUBERT_MODEL_NAME=facebook/hubert-large-ls960-ft
HUBERT_DEVICE=cpu

# Qwen: English Grammar/Fluency/Vocabulary
QWEN_MODEL_NAME=
# Leave empty to use base model on DL-Model-Support server
# Set to finetuned model path when available

# LLaMA3-VI: Vietnamese Explanations (lazy load)
LLAMA_MODEL_NAME=vilm/vinallama-7b-chat

# ============================================================
# Database Configurations
# ============================================================

# MongoDB
MONGODB_URI=mongodb://localhost:27017
MONGODB_DATABASE=lexilingo_dev

# Redis
REDIS_URL=redis://localhost:6379/0
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_DB=0

# KuzuDB
KUZU_DB_PATH=./api/data/kuzu

# ============================================================
# API Configurations
# ============================================================

# DL-Model-Support Integration
AI_MODEL_API_URL=http://localhost:8001
AI_MODEL_API_KEY=

# Environment
ENVIRONMENT=development
DEBUG=false
LOG_LEVEL=INFO

# CORS
ALLOWED_ORIGINS=["http://localhost:3000","http://localhost:8080"]
"""
    
    with open(env_path, 'w') as f:
        f.write(env_content)
    
    print(f" Created .env file at {env_path}")
    return True


def main():
    """Main download script"""
    print("""
╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║            LexiLingo Model Download Script                 ║
║                                                                ║
║  This script will download all required AI models:             ║
║  • Faster-Whisper large-v3 (STT) - 3.1GB                       ║
║  • Sentence-Transformers (Embeddings) - 22MB                   ║
║  • HuBERT (Pronunciation) - 960MB                              ║
║  • Piper (TTS) - 60MB                                          ║
║  • Vietnamese LLaMA (optional) - 8GB                           ║
║                                                                ║
║  Total download: ~4.1GB (without Vietnamese model)             ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
    """)
    
    # Change to backend directory
    backend_dir = Path(__file__).parent.parent
    os.chdir(backend_dir)
    print(f" Working directory: {backend_dir.absolute()}")
    
    # Create models directory
    models_dir = Path("./models")
    models_dir.mkdir(exist_ok=True)
    print(f" Models directory: {models_dir.absolute()}")
    
    # Track results
    results = []
    
    # Download each model
    results.append(("Faster-Whisper", download_whisper()))
    results.append(("Sentence-Transformers", download_sentence_transformers()))
    results.append(("HuBERT", download_hubert()))
    results.append(("Piper TTS", download_piper_voice()))
    results.append(("Vietnamese LLaMA", download_vietnamese_model()))
    
    # Create .env file
    results.append((".env Configuration", create_env_file()))
    
    # Summary
    print("\n" + "="*60)
    print("DOWNLOAD SUMMARY")
    print("="*60)
    
    success_count = sum(1 for _, success in results if success)
    total_count = len(results)
    
    for name, success in results:
        status = "" if success else ""
        print(f"{status} {name}")
    
    print("="*60)
    print(f" {success_count}/{total_count} tasks completed successfully")
    
    if success_count == total_count:
        print("\n All models downloaded successfully!")
        print("\n Next steps:")
        print("   1. Review and adjust .env file if needed")
        print("   2. Start the backend: python -m uvicorn api.main:app --reload")
        print("   3. Test endpoints: /api/v1/stt/transcribe, /api/v1/tts/synthesize")
    else:
        print("\n️  Some downloads failed. Check error messages above.")
    
    print("\n" + "="*60)


if __name__ == "__main__":
    main()
