"""Configuration loader with environment variable support"""

import os
import yaml
from pathlib import Path
from typing import Any, Optional
from string import Template


class Config:
    """Configuration manager"""
    
    _instance = None
    _config = {}
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance
    
    @classmethod
    def load(cls, config_path: str = "config.yaml") -> "Config":
        """Load configuration from YAML file"""
        instance = cls()
        
        config_file = Path(config_path)
        if not config_file.exists():
            raise FileNotFoundError(f"Config file not found: {config_path}")
        
        with open(config_file, "r") as f:
            raw_config = yaml.safe_load(f)
        
        # Resolve environment variables
        instance._config = cls._resolve_env_vars(raw_config)
        
        return instance
    
    @staticmethod
    def _resolve_env_vars(config: dict) -> dict:
        """Recursively resolve ${VAR} patterns with environment variables"""
        if isinstance(config, dict):
            return {k: Config._resolve_env_vars(v) for k, v in config.items()}
        elif isinstance(config, list):
            return [Config._resolve_env_vars(item) for item in config]
        elif isinstance(config, str) and "${" in config:
            # Use Template to substitute environment variables
            template = Template(config)
            return template.safe_substitute(os.environ)
        else:
            return config
    
    def get(self, key: str, default: Any = None) -> Any:
        """
        Get configuration value by dot-separated key
        Example: config.get("models.qwen.name")
        """
        keys = key.split(".")
        value = self._config
        
        for k in keys:
            if isinstance(value, dict) and k in value:
                value = value[k]
            else:
                return default
        
        return value
    
    def set(self, key: str, value: Any) -> None:
        """Set configuration value"""
        keys = key.split(".")
        config = self._config
        
        for k in keys[:-1]:
            if k not in config:
                config[k] = {}
            config = config[k]
        
        config[keys[-1]] = value
    
    def __getitem__(self, key: str) -> Any:
        """Allow dict-like access"""
        return self.get(key)
    
    def __setitem__(self, key: str, value: Any) -> None:
        """Allow dict-like setting"""
        self.set(key, value)
    
    def to_dict(self) -> dict:
        """Return full configuration as dict"""
        return self._config.copy()
