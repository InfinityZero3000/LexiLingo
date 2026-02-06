"""
Smart Ollama Configuration - Optimize cho Intel Mac
"""

# Tối ưu cho Qwen3-4B-Thinking
OLLAMA_OPTIMIZATIONS = {
    # Streaming cho perceived speed
    "stream": True,  # Return tokens ngay khi có
    
    # Thread optimization
    "num_thread": 8,  # Match physical cores
    
    # Context giảm từ 262K → 4K cho speed
    "num_ctx": 4096,  # Đủ cho English teaching
    
    # Generation control
    "num_predict": 256,  # Max tokens to generate
    "temperature": 0.7,
    "top_p": 0.9,
    "top_k": 40,
    
    # Timeout & keep alive
    "timeout": 15,  # Fail fast → fallback Gemini
    "keep_alive": "5m",  # Unload sau 5 phút
}

# Fast model alternatives
RECOMMENDED_FAST_MODELS = [
    {
        "name": "phi-3:mini",
        "size": "2.3GB",
        "speed": "~3-5s",
        "quality": "Good for teaching",
        "command": "ollama pull phi-3:mini",
    },
    {
        "name": "gemma2:2b", 
        "size": "1.6GB",
        "speed": "~2-4s",
        "quality": "Fast, decent",
        "command": "ollama pull gemma2:2b",
    },
    {
        "name": "tinyllama:1.1b",
        "size": "637MB",
        "speed": "~1-2s",
        "quality": "Basic only",
        "command": "ollama pull tinyllama",
    },
]

# Intelligent routing rules
ROUTING_RULES = {
    "simple": {
        "keywords": ["hi", "hello", "thanks", "bye"],
        "max_words": 10,
        "model": "local",  # Fast local model OK
    },
    "grammar": {
        "keywords": ["grammar", "mistake", "correct"],
        "model": "gemini",  # Need high quality
    },
    "complex": {
        "min_words": 50,
        "model": "gemini",  # Long context → cloud
    },
}
