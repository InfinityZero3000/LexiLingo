"""
Base Course Crawler
Provides common functionality for all course crawlers
"""
import os
import time
import logging
import json
from typing import List, Dict, Optional
from urllib.parse import urljoin, urlparse
from datetime import datetime
import requests
from bs4 import BeautifulSoup
import yaml


class BaseCrawler:
    """Base class for all course crawlers"""
    
    def __init__(self, config_path: str = None):
        """Initialize the crawler with configuration"""
        if config_path is None:
            # Get the directory where this script is located
            script_dir = os.path.dirname(os.path.abspath(__file__))
            config_path = os.path.join(script_dir, "config.yaml")
        
        self.config = self._load_config(config_path)
        self.session = requests.Session()
        self.logger = self._setup_logger()
        
        # Set user agent
        user_agent = self.config['global']['user_agent']
        self.session.headers.update({'User-Agent': user_agent})
        
        # Rate limiting
        self.rate_limit = self.config['global']['rate_limit_seconds']
        self.last_request_time = 0
        
        # Request settings
        self.max_retries = self.config['global']['max_retries']
        self.timeout = self.config['global']['timeout_seconds']
    
    def _load_config(self, config_path: str) -> dict:
        """Load configuration from YAML file"""
        with open(config_path, 'r', encoding='utf-8') as f:
            return yaml.safe_load(f)
    
    def _setup_logger(self) -> logging.Logger:
        """Setup logging configuration"""
        # Create logs directory if it doesn't exist
        log_dir = self.config['output']['log_dir']
        os.makedirs(log_dir, exist_ok=True)
        
        # Configure logger
        logger = logging.getLogger(self.__class__.__name__)
        logger.setLevel(logging.INFO)
        
        # File handler
        log_file = os.path.join(log_dir, f"{self.__class__.__name__}_{datetime.now().strftime('%Y%m%d')}.log")
        file_handler = logging.FileHandler(log_file)
        file_handler.setLevel(logging.INFO)
        
        # Console handler
        console_handler = logging.StreamHandler()
        console_handler.setLevel(logging.INFO)
        
        # Formatter
        formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
        file_handler.setFormatter(formatter)
        console_handler.setFormatter(formatter)
        
        logger.addHandler(file_handler)
        logger.addHandler(console_handler)
        
        return logger
    
    def _respect_rate_limit(self):
        """Ensure we respect rate limiting"""
        elapsed = time.time() - self.last_request_time
        if elapsed < self.rate_limit:
            time.sleep(self.rate_limit - elapsed)
        self.last_request_time = time.time()
    
    def _make_request(self, url: str, method: str = 'GET', **kwargs) -> Optional[requests.Response]:
        """Make HTTP request with retry logic and error handling"""
        self._respect_rate_limit()
        
        for attempt in range(self.max_retries):
            try:
                self.logger.info(f"Requesting {url} (attempt {attempt + 1}/{self.max_retries})")
                
                if method.upper() == 'GET':
                    response = self.session.get(url, timeout=self.timeout, **kwargs)
                else:
                    response = self.session.post(url, timeout=self.timeout, **kwargs)
                
                response.raise_for_status()
                return response
                
            except requests.exceptions.RequestException as e:
                self.logger.warning(f"Request failed (attempt {attempt + 1}/{self.max_retries}): {e}")
                if attempt < self.max_retries - 1:
                    time.sleep(2 ** attempt)  # Exponential backoff
                else:
                    self.logger.error(f"All retry attempts failed for {url}")
                    return None
        
        return None
    
    def _parse_html(self, html_content: str) -> Optional[BeautifulSoup]:
        """Parse HTML content using BeautifulSoup"""
        try:
            return BeautifulSoup(html_content, 'html.parser')
        except Exception as e:
            self.logger.error(f"Failed to parse HTML: {e}")
            return None
    
    def _save_raw_data(self, data: str, filename: str):
        """Save raw HTML/JSON data for debugging"""
        raw_dir = self.config['output']['raw_dir']
        os.makedirs(raw_dir, exist_ok=True)
        
        filepath = os.path.join(raw_dir, filename)
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(data)
        
        self.logger.info(f"Saved raw data to {filepath}")
    
    def _save_courses(self, courses: List[Dict], filename: str):
        """Save courses to JSON file"""
        courses_dir = self.config['output']['courses_dir']
        os.makedirs(courses_dir, exist_ok=True)
        
        filepath = os.path.join(courses_dir, filename)
        with open(filepath, 'w', encoding='utf-8') as f:
            json.dump(courses, f, ensure_ascii=False, indent=2)
        
        self.logger.info(f"Saved {len(courses)} courses to {filepath}")
        return filepath
    
    def check_robots_txt(self, base_url: str) -> bool:
        """Check if crawling is allowed by robots.txt"""
        try:
            robots_url = urljoin(base_url, '/robots.txt')
            response = self._make_request(robots_url)
            
            if response:
                # Simple check - in production, use robotparser
                content = response.text.lower()
                user_agent_section = False
                
                for line in content.split('\n'):
                    line = line.strip()
                    if line.startswith('user-agent:'):
                        ua = line.split(':', 1)[1].strip()
                        user_agent_section = ua == '*' or 'bot' in ua
                    elif user_agent_section and line.startswith('disallow:'):
                        disallow_path = line.split(':', 1)[1].strip()
                        if disallow_path == '/':
                            self.logger.warning(f"Crawling disallowed by robots.txt for {base_url}")
                            return False
                
                self.logger.info(f"Crawling allowed by robots.txt for {base_url}")
                return True
            
        except Exception as e:
            self.logger.warning(f"Could not check robots.txt: {e}")
        
        # If we can't check, be conservative and allow
        return True
    
    def crawl(self) -> List[Dict]:
        """
        Main crawl method - to be implemented by subclasses
        Returns list of course dictionaries
        """
        raise NotImplementedError("Subclasses must implement crawl() method")
    
    def normalize_level(self, level: str) -> str:
        """Normalize course level to standard format"""
        level = level.lower().strip()
        
        level_mapping = {
            'a1': 'Beginner',
            'a2': 'Elementary',
            'b1': 'Pre-Intermediate',
            'b2': 'Intermediate',
            'c1': 'Upper-Intermediate',
            'c2': 'Advanced',
            'beginner': 'Beginner',
            'elementary': 'Elementary',
            'pre-intermediate': 'Pre-Intermediate',
            'intermediate': 'Intermediate',
            'upper intermediate': 'Upper-Intermediate',
            'upper-intermediate': 'Upper-Intermediate',
            'advanced': 'Advanced',
        }
        
        return level_mapping.get(level, 'Intermediate')
