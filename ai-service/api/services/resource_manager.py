"""
Resource Manager for AI Models

Manages GPU/CPU/Memory allocation for AI models.
Supports lazy loading and resource tracking.

Following architecture.md principles:
- Qwen: 1.6GB (always loaded)
- HuBERT: 2.0GB (lazy load for voice)
- LLaMA3-VI: 4.0GB (lazy load for Vietnamese)
"""

import logging
from typing import Dict, Optional, Set
import psutil
import asyncio

logger = logging.getLogger(__name__)


class ResourceManager:
    """
    Quản lý tài nguyên GPU/CPU/Memory cho AI models.
    
    Features:
    - Memory tracking và budget management
    - Model loading/unloading coordination
    - Resource availability checking
    - GPU/CPU utilization monitoring
    """
    
    def __init__(self, max_memory_gb: float = 8.0):
        """
        Initialize Resource Manager.
        
        Args:
            max_memory_gb: Maximum memory budget in GB (default: 8GB)
        """
        self.max_memory_gb = max_memory_gb
        self.current_usage_gb = 0.0
        self.loaded_models: Set[str] = set()
        
        # Model memory sizes (in GB)
        self.model_sizes = {
            "qwen": 1.6,       # Qwen2.5-1.5B + Unified LoRA
            "hubert": 2.0,     # HuBERT-large
            "llama": 4.0,      # LLaMA3-8B-VI (4-bit quantization)
            "whisper": 0.3,    # Faster-Whisper small
            "piper": 0.1       # Piper TTS
        }
        
        # Model priorities (higher = more important)
        self.model_priorities = {
            "qwen": 10,        # Critical - always keep
            "whisper": 8,      # High - needed for voice
            "hubert": 5,       # Medium - pronunciation only
            "piper": 7,        # Medium-high - TTS
            "llama": 3         # Low - Vietnamese only
        }
        
        logger.info(f"ResourceManager initialized with {max_memory_gb}GB budget")
    
    def can_load_model(self, model_name: str, required_gb: Optional[float] = None) -> bool:
        """
        Check if có đủ memory để load model.
        
        Args:
            model_name: Name of model to load
            required_gb: Memory required (if None, use default from model_sizes)
            
        Returns:
            True if enough memory available
        """
        if model_name in self.loaded_models:
            logger.debug(f"Model {model_name} already loaded")
            return True
        
        # Get required memory
        if required_gb is None:
            required_gb = self.model_sizes.get(model_name, 0.0)
        
        # Check available memory
        available_gb = self.max_memory_gb - self.current_usage_gb
        can_load = available_gb >= required_gb
        
        if can_load:
            logger.info(
                f"Can load {model_name} ({required_gb}GB). "
                f"Available: {available_gb:.2f}GB"
            )
        else:
            logger.warning(
                f"Cannot load {model_name} ({required_gb}GB). "
                f"Available: {available_gb:.2f}GB. Need to free memory."
            )
        
        return can_load
    
    def allocate_memory(self, model_name: str, size_gb: Optional[float] = None):
        """
        Allocate memory for model.
        
        Args:
            model_name: Name of model
            size_gb: Memory size (if None, use default)
        """
        if model_name in self.loaded_models:
            logger.warning(f"Model {model_name} already allocated")
            return
        
        # Get size
        if size_gb is None:
            size_gb = self.model_sizes.get(model_name, 0.0)
        
        # Allocate
        self.current_usage_gb += size_gb
        self.loaded_models.add(model_name)
        
        logger.info(
            f"✓ Allocated {size_gb}GB for {model_name}. "
            f"Total usage: {self.current_usage_gb:.2f}GB / {self.max_memory_gb}GB "
            f"({self.get_usage_percent():.1f}%)"
        )
    
    def release_memory(self, model_name: str):
        """
        Release memory from model.
        
        Args:
            model_name: Name of model to release
        """
        if model_name not in self.loaded_models:
            logger.warning(f"Model {model_name} not loaded")
            return
        
        # Get size
        size_gb = self.model_sizes.get(model_name, 0.0)
        
        # Release
        self.current_usage_gb = max(0.0, self.current_usage_gb - size_gb)
        self.loaded_models.discard(model_name)
        
        logger.info(
            f"✓ Released {size_gb}GB from {model_name}. "
            f"Total usage: {self.current_usage_gb:.2f}GB / {self.max_memory_gb}GB"
        )
    
    async def auto_manage_memory(self, required_model: str) -> bool:
        """
        Automatically manage memory by unloading low-priority models.
        
        Args:
            required_model: Model that needs to be loaded
            
        Returns:
            True if successfully managed to free enough memory
        """
        required_gb = self.model_sizes.get(required_model, 0.0)
        
        # Check if already loadable
        if self.can_load_model(required_model, required_gb):
            return True
        
        logger.info(f"Auto-managing memory to load {required_model}...")
        
        # Calculate how much memory to free
        available = self.max_memory_gb - self.current_usage_gb
        needed = required_gb - available
        
        # Sort loaded models by priority (lowest first)
        loaded_by_priority = sorted(
            self.loaded_models,
            key=lambda m: self.model_priorities.get(m, 0)
        )
        
        # Try to unload low-priority models
        freed = 0.0
        for model in loaded_by_priority:
            if freed >= needed:
                break
            
            # Don't unload critical models
            if self.model_priorities.get(model, 0) >= 10:
                continue
            
            model_size = self.model_sizes.get(model, 0.0)
            logger.info(f"Unloading {model} ({model_size}GB) to free memory...")
            self.release_memory(model)
            freed += model_size
        
        # Check if we freed enough
        success = freed >= needed
        if success:
            logger.info(f"✓ Freed {freed:.2f}GB by unloading {int(freed/2)} models")
        else:
            logger.warning(f"✗ Only freed {freed:.2f}GB, need {needed:.2f}GB")
        
        return success
    
    def get_usage_percent(self) -> float:
        """Get current memory usage percentage."""
        if self.max_memory_gb == 0:
            return 0.0
        return (self.current_usage_gb / self.max_memory_gb) * 100
    
    def get_usage_stats(self) -> Dict[str, any]:
        """
        Get detailed usage statistics.
        
        Returns:
            Dict with usage stats including loaded models
        """
        # Get system memory info
        system_memory = psutil.virtual_memory()
        
        return {
            "budget": {
                "total_gb": self.max_memory_gb,
                "used_gb": round(self.current_usage_gb, 2),
                "available_gb": round(self.max_memory_gb - self.current_usage_gb, 2),
                "usage_percent": round(self.get_usage_percent(), 1)
            },
            "loaded_models": list(self.loaded_models),
            "model_count": len(self.loaded_models),
            "system_memory": {
                "total_gb": round(system_memory.total / (1024**3), 2),
                "available_gb": round(system_memory.available / (1024**3), 2),
                "used_percent": system_memory.percent
            }
        }
    
    def is_critical_model(self, model_name: str) -> bool:
        """Check if model is critical (should not be unloaded)."""
        return self.model_priorities.get(model_name, 0) >= 10
    
    def get_model_info(self, model_name: str) -> Dict[str, any]:
        """Get information about a specific model."""
        return {
            "name": model_name,
            "size_gb": self.model_sizes.get(model_name, 0.0),
            "priority": self.model_priorities.get(model_name, 0),
            "is_loaded": model_name in self.loaded_models,
            "is_critical": self.is_critical_model(model_name)
        }
    
    def reset(self):
        """Reset resource manager (for testing)."""
        self.current_usage_gb = 0.0
        self.loaded_models.clear()
        logger.info("ResourceManager reset")


# Singleton instance
_resource_manager: Optional[ResourceManager] = None


def get_resource_manager(max_memory_gb: float = 8.0) -> ResourceManager:
    """
    Get ResourceManager singleton.
    
    Args:
        max_memory_gb: Memory budget (only used on first call)
        
    Returns:
        ResourceManager instance
    """
    global _resource_manager
    
    if _resource_manager is None:
        _resource_manager = ResourceManager(max_memory_gb)
    
    return _resource_manager
