"""
BBC Learning English Crawler
Crawls courses from BBC Learning English website
"""
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from typing import List, Dict, Optional
from datetime import datetime
from course_crawler import BaseCrawler


class BBCLearningEnglishCrawler(BaseCrawler):
    """Crawler for BBC Learning English courses"""
    
    def __init__(self, config_path: str = None):
        if config_path is None:
            # Get the parent directory (crawler root)
            script_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            config_path = os.path.join(script_dir, "config.yaml")
        
        super().__init__(config_path)
        self.source_config = self.config['sources']['bbc_learning_english']
        self.base_url = self.source_config['base_url']
        
        # Override rate limit with source-specific setting
        self.rate_limit = self.source_config.get('rate_limit_seconds', self.rate_limit)
    
    def crawl(self, limit: Optional[int] = None) -> List[Dict]:
        """Crawl BBC Learning English courses"""
        self.logger.info("Starting BBC Learning English crawler...")
        
        # Check robots.txt
        if not self.check_robots_txt(self.base_url):
            self.logger.error("Crawling not allowed by robots.txt")
            return []
        
        courses = []
        
        # BBC Learning English has multiple course series
        course_series = [
            {
                'name': 'English at Work',
                'url': 'https://www.bbc.co.uk/learningenglish/english/course/english-at-work',
                'level': 'Intermediate',
                'category': 'Business English',
                'description': 'Learn useful business English phrases and improve your workplace communication skills in this drama series.',
            },
            {
                'name': '6 Minute English',
                'url': 'https://www.bbc.co.uk/learningenglish/english/features/6-minute-english',
                'level': 'Intermediate',
                'category': 'Listening',
                'description': 'Learn and practise useful English language for everyday situations with BBC Learning English.',
            },
            {
                'name': 'English in a Minute',
                'url': 'https://www.bbc.co.uk/learningenglish/english/course/eiam',
                'level': 'Beginner',
                'category': 'Quick Lessons',
                'description': 'Learn English with short 1-minute videos covering grammar, vocabulary and pronunciation.',
            },
            {
                'name': 'The English We Speak',
                'url': 'https://www.bbc.co.uk/learningenglish/english/course/tews',
                'level': 'Intermediate',
                'category': 'Vocabulary',
                'description': 'Learn common English idioms and phrases with fun and engaging audio lessons.',
            },
            {
                'name': 'Everyday English',
                'url': 'https://www.bbc.co.uk/learningenglish/english/course/ee',
                'level': 'Elementary',
                'category': 'Conversation',
                'description': 'Master everyday English conversations for common situations.',
            },
            {
                'name': 'Grammar Reference',
                'url': 'https://www.bbc.co.uk/learningenglish/english/course/intermediate-grammar',
                'level': 'Intermediate',
                'category': 'Grammar',
                'description': 'Comprehensive English grammar lessons with explanations, examples and practice exercises.',
            },
            {
                'name': 'Lower Intermediate Grammar',
                'url': 'https://www.bbc.co.uk/learningenglish/english/course/lower-intermediate',
                'level': 'Pre-Intermediate',
                'category': 'Grammar',
                'description': 'Essential grammar for lower intermediate English learners.',
            },
            {
                'name': 'Upper Intermediate Grammar',
                'url': 'https://www.bbc.co.uk/learningenglish/english/course/upper-intermediate',
                'level': 'Upper-Intermediate',
                'category': 'Grammar',
                'description': 'Advanced grammar topics for upper intermediate learners.',
            },
            {
                'name': 'English at University',
                'url': 'https://www.bbc.co.uk/learningenglish/english/course/english-at-university',
                'level': 'Intermediate',
                'category': 'Academic English',
                'description': 'Learn academic English skills for university students including presentations, essays and seminars.',
            },
            {
                'name': 'News Review',
                'url': 'https://www.bbc.co.uk/learningenglish/english/course/newsreview',
                'level': 'Upper-Intermediate',
                'category': 'Current Affairs',
                'description': 'Learn vocabulary and phrases from the latest news stories.',
            },
            {
                'name': 'Pronunciation',
                'url': 'https://www.bbc.co.uk/learningenglish/english/course/pronunciation',
                'level': 'Intermediate',
                'category': 'Pronunciation',
                'description': 'Improve your English pronunciation with detailed lessons and practice.',
            },
            {
                'name': 'Business English',
                'url': 'https://www.bbc.co.uk/learningenglish/english/features/business-english',
                'level': 'Intermediate',
                'category': 'Business English',
                'description': 'Essential business English for professional communication.',
            },
        ]
        
        for idx, series in enumerate(course_series):
            if limit and idx >= limit:
                break
            
            self.logger.info(f"Processing course: {series['name']}")
            
            # Fetch course page to get more details
            course_data = self._scrape_course_details(series)
            if course_data:
                courses.append(course_data)
        
        # Save courses
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        filename = f"bbc_courses_{timestamp}.json"
        self._save_courses(courses, filename)
        
        return courses
    
    def _scrape_course_details(self, series: Dict) -> Optional[Dict]:
        """Scrape detailed information for a course"""
        try:
            response = self._make_request(series['url'])
            if not response:
                return self._create_course_dict(series)
            
            # Save raw HTML
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            raw_filename = f"bbc_{series['name'].replace(' ', '_')}_{timestamp}.html"
            self._save_raw_data(response.text, raw_filename)
            
            # Parse HTML
            soup = self._parse_html(response.text)
            if not soup:
                return self._create_course_dict(series)
            
            # Try to extract episode/lesson count
            lessons_count = self._extract_lessons_count(soup)
            
            # Try to find course image
            image_url = self._extract_image_url(soup)
            
            # Create course dictionary with scraped data
            course = self._create_course_dict(series, lessons_count, image_url)
            
            return course
            
        except Exception as e:
            self.logger.error(f"Error scraping {series['name']}: {e}")
            return self._create_course_dict(series)
    
    def _extract_lessons_count(self, soup) -> int:
        """Extract number of lessons from page"""
        try:
            # Try to find episode/lesson count
            # BBC course pages have different structures, so we try multiple selectors
            
            # Look for episode lists
            episodes = soup.find_all(['div', 'article', 'section'], class_=lambda x: x and ('episode' in x.lower() or 'unit' in x.lower()))
            if episodes:
                return len(episodes)
            
            # Look for session/unit lists
            sessions = soup.find_all(['div', 'article', 'section'], class_=lambda x: x and ('session' in x.lower() or 'unit' in x.lower()))
            if sessions:
                return len(sessions)
            
            # Default estimate based on course type
            return 10
            
        except Exception as e:
            self.logger.debug(f"Could not extract lesson count: {e}")
            return 10
    
    def _extract_image_url(self, soup) -> Optional[str]:
        """Extract course image URL"""
        try:
            # Look for Open Graph image
            og_image = soup.find('meta', property='og:image')
            if og_image and og_image.get('content'):
                return og_image['content']
            
            # Look for main course image
            img = soup.find('img', class_=lambda x: x and ('course' in x.lower() or 'hero' in x.lower() or 'banner' in x.lower()))
            if img and img.get('src'):
                src = img['src']
                if src.startswith('//'):
                    return 'https:' + src
                elif src.startswith('/'):
                    return self.base_url + src
                return src
            
            # BBC default logo
            return 'https://www.bbc.co.uk/learningenglish/images/logos/bbc-learning-english-logo.svg'
            
        except Exception as e:
            self.logger.debug(f"Could not extract image URL: {e}")
            return None
    
    def _create_course_dict(self, series: Dict, lessons_count: int = 10, image_url: Optional[str] = None) -> Dict:
        """Create course dictionary matching Flutter Course model"""
        return {
            'title': series['name'],
            'description': series['description'],
            'level': series['level'],
            'category': series.get('category', 'General English'),
            'imageUrl': image_url or 'https://www.bbc.co.uk/learningenglish/images/logos/bbc-learning-english-logo.svg',
            'duration': self._estimate_duration(lessons_count),
            'lessonsCount': lessons_count,
            'isFeatured': series['name'] in ['6 Minute English', 'English at Work'],  # Feature popular courses
            'rating': 4.5,  # BBC courses are generally high quality
            'enrolledCount': 0,  # Will be updated when users enroll
            'createdAt': datetime.now().isoformat(),
            'updatedAt': datetime.now().isoformat(),
            'source': 'BBC Learning English',
            'sourceUrl': series['url'],
        }
    
    def _estimate_duration(self, lessons_count: int) -> str:
        """Estimate course duration based on lesson count"""
        # Assume average 10 minutes per lesson
        total_minutes = lessons_count * 10
        
        if total_minutes < 60:
            return f"{total_minutes} minutes"
        else:
            hours = total_minutes // 60
            minutes = total_minutes % 60
            if minutes > 0:
                return f"{hours}h {minutes}m"
            return f"{hours} hours"


if __name__ == "__main__":
    # Test the crawler
    crawler = BBCLearningEnglishCrawler()
    courses = crawler.crawl(limit=5)
    print(f"\nCrawled {len(courses)} courses from BBC Learning English")
    for course in courses:
        print(f"- {course['title']} ({course['level']}) - {course['lessonsCount']} lessons")
