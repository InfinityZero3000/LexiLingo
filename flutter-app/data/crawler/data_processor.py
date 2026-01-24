"""
Data Processor and Validator
Validates and processes crawled course data
"""
import json
import logging
from typing import List, Dict, Optional
from datetime import datetime
import yaml


class CourseDataProcessor:
    """Process and validate course data"""
    
    def __init__(self, config_path: str = None):
        """Initialize processor with configuration"""
        if config_path is None:
            # Get the directory where this script is located
            script_dir = os.path.dirname(os.path.abspath(__file__))
            config_path = os.path.join(script_dir, "config.yaml")
        
        with open(config_path, 'r', encoding='utf-8') as f:
            self.config = yaml.safe_load(f)
        
        self.validation_rules = self.config['validation']
        self.logger = self._setup_logger()
    
    def _setup_logger(self) -> logging.Logger:
        """Setup logging"""
        logger = logging.getLogger('CourseDataProcessor')
        logger.setLevel(logging.INFO)
        
        if not logger.handlers:
            handler = logging.StreamHandler()
            formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
            handler.setFormatter(formatter)
            logger.addHandler(handler)
        
        return logger
    
    def validate_course(self, course: Dict) -> tuple[bool, List[str]]:
        """
        Validate a single course against schema and rules
        Returns: (is_valid, list_of_errors)
        """
        errors = []
        
        # Check required fields
        required_fields = ['title', 'description', 'level']
        for field in required_fields:
            if field not in course or not course[field]:
                errors.append(f"Missing required field: {field}")
        
        if errors:
            return False, errors
        
        # Validate title length
        title_len = len(course['title'])
        if title_len < self.validation_rules['min_title_length']:
            errors.append(f"Title too short: {title_len} chars (min: {self.validation_rules['min_title_length']})")
        elif title_len > self.validation_rules['max_title_length']:
            errors.append(f"Title too long: {title_len} chars (max: {self.validation_rules['max_title_length']})")
        
        # Validate description length
        desc_len = len(course['description'])
        if desc_len < self.validation_rules['min_description_length']:
            errors.append(f"Description too short: {desc_len} chars (min: {self.validation_rules['min_description_length']})")
        elif desc_len > self.validation_rules['max_description_length']:
            errors.append(f"Description too long: {desc_len} chars (max: {self.validation_rules['max_description_length']})")
        
        # Validate level
        valid_levels = self.validation_rules['valid_levels']
        if course['level'] not in valid_levels:
            errors.append(f"Invalid level: {course['level']} (must be one of {valid_levels})")
        
        # Validate numeric fields
        if 'lessonsCount' in course:
            if not isinstance(course['lessonsCount'], int) or course['lessonsCount'] < 0:
                errors.append(f"Invalid lessonsCount: {course['lessonsCount']}")
        
        if 'rating' in course:
            if not isinstance(course['rating'], (int, float)) or course['rating'] < 0 or course['rating'] > 5:
                errors.append(f"Invalid rating: {course['rating']} (must be 0-5)")
        
        return len(errors) == 0, errors
    
    def process_courses(self, courses: List[Dict]) -> tuple[List[Dict], Dict]:
        """
        Process and validate a list of courses
        Returns: (valid_courses, stats)
        """
        valid_courses = []
        stats = {
            'total': len(courses),
            'valid': 0,
            'invalid': 0,
            'duplicates': 0,
            'errors': []
        }
        
        seen_titles = set()
        
        for idx, course in enumerate(courses):
            # Validate
            is_valid, errors = self.validate_course(course)
            
            if not is_valid:
                stats['invalid'] += 1
                stats['errors'].append({
                    'course_index': idx,
                    'title': course.get('title', 'Unknown'),
                    'errors': errors
                })
                self.logger.warning(f"Invalid course: {course.get('title', 'Unknown')} - {errors}")
                continue
            
            # Check for duplicates
            title_lower = course['title'].lower()
            if title_lower in seen_titles:
                stats['duplicates'] += 1
                self.logger.info(f"Duplicate course skipped: {course['title']}")
                continue
            
            seen_titles.add(title_lower)
            
            # Enrich course data
            enriched_course = self._enrich_course(course)
            valid_courses.append(enriched_course)
            stats['valid'] += 1
        
        self.logger.info(f"Processing complete: {stats['valid']} valid, {stats['invalid']} invalid, {stats['duplicates']} duplicates")
        return valid_courses, stats
    
    def _enrich_course(self, course: Dict) -> Dict:
        """Enrich course data with additional computed fields"""
        enriched = course.copy()
        
        # Ensure all optional fields have default values
        enriched.setdefault('category', 'General English')
        enriched.setdefault('imageUrl', None)
        enriched.setdefault('duration', 'Varies')
        enriched.setdefault('lessonsCount', 0)
        enriched.setdefault('isFeatured', False)
        enriched.setdefault('rating', 0.0)
        enriched.setdefault('enrolledCount', 0)
        enriched.setdefault('createdAt', datetime.now().isoformat())
        enriched.setdefault('updatedAt', datetime.now().isoformat())
        
        # Clean and normalize text fields
        enriched['title'] = enriched['title'].strip()
        enriched['description'] = enriched['description'].strip()
        
        return enriched
    
    def merge_course_lists(self, course_lists: List[List[Dict]]) -> List[Dict]:
        """Merge multiple course lists, removing duplicates"""
        all_courses = []
        seen_titles = set()
        
        for course_list in course_lists:
            for course in course_list:
                title_lower = course['title'].lower()
                if title_lower not in seen_titles:
                    all_courses.append(course)
                    seen_titles.add(title_lower)
        
        self.logger.info(f"Merged {len(all_courses)} unique courses from {len(course_lists)} sources")
        return all_courses
    
    def export_to_flutter_format(self, courses: List[Dict], output_path: str):
        """Export courses in format compatible with Flutter Course model"""
        # Remove source-specific fields before export
        flutter_courses = []
        
        for course in courses:
            flutter_course = {
                'title': course['title'],
                'description': course['description'],
                'level': course['level'],
                'category': course.get('category'),
                'imageUrl': course.get('imageUrl'),
                'duration': course.get('duration'),
                'lessonsCount': course.get('lessonsCount', 0),
                'isFeatured': course.get('isFeatured', False),
                'rating': course.get('rating', 0.0),
                'enrolledCount': course.get('enrolledCount', 0),
                'createdAt': course.get('createdAt'),
                'updatedAt': course.get('updatedAt'),
            }
            flutter_courses.append(flutter_course)
        
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(flutter_courses, f, ensure_ascii=False, indent=2)
        
        self.logger.info(f"Exported {len(flutter_courses)} courses to {output_path}")
        return output_path


if __name__ == "__main__":
    # Test the processor
    processor = CourseDataProcessor()
    
    # Sample course data
    test_courses = [
        {
            'title': 'Test Course 1',
            'description': 'This is a test course with sufficient description length for validation.',
            'level': 'Intermediate',
            'lessonsCount': 10,
            'rating': 4.5
        },
        {
            'title': 'Bad',  # Too short title
            'description': 'This is a test course with sufficient description length for validation.',
            'level': 'Intermediate',
        },
        {
            'title': 'Test Course with Invalid Level',
            'description': 'This is a test course with sufficient description length for validation.',
            'level': 'SuperAdvanced',  # Invalid level
        }
    ]
    
    valid, stats = processor.process_courses(test_courses)
    print(f"\nValidation Results:")
    print(f"Total: {stats['total']}")
    print(f"Valid: {stats['valid']}")
    print(f"Invalid: {stats['invalid']}")
    print(f"\nErrors: {json.dumps(stats['errors'], indent=2)}")
