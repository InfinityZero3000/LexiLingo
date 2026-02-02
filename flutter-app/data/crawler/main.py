"""
Main Crawler Entry Point
Run course crawlers and process data
"""
import sys
import os
import argparse
import json
from datetime import datetime
from typing import List, Dict

# Add current directory to path
current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, current_dir)

from sources.bbc_learning_english_crawler import BBCLearningEnglishCrawler
from data_processor import CourseDataProcessor


def crawl_bbc(limit: int = None) -> List[Dict]:
    """Crawl BBC Learning English courses"""
    print("\n" + "="*60)
    print("BBC LEARNING ENGLISH CRAWLER")
    print("="*60)
    
    crawler = BBCLearningEnglishCrawler()
    courses = crawler.crawl(limit=limit)
    
    print(f"\n✓ Crawled {len(courses)} courses from BBC Learning English")
    return courses


def process_and_export(courses: List[Dict], output_filename: str = None):
    """Process and export courses"""
    print("\n" + "="*60)
    print("PROCESSING AND VALIDATING DATA")
    print("="*60)
    
    processor = CourseDataProcessor()
    
    # Process courses
    valid_courses, stats = processor.process_courses(courses)
    
    print(f"\nProcessing Statistics:")
    print(f"   Total courses: {stats['total']}")
    print(f"   ✓ Valid: {stats['valid']}")
    print(f"   ✗ Invalid: {stats['invalid']}")
    print(f"   ⚠ Duplicates: {stats['duplicates']}")
    
    if stats['errors']:
        print(f"\n⚠ Validation Errors:")
        for error in stats['errors'][:5]:  # Show first 5 errors
            print(f"   - {error['title']}: {', '.join(error['errors'])}")
        if len(stats['errors']) > 5:
            print(f"   ... and {len(stats['errors']) - 5} more errors")
    
    # Export to Flutter format
    if not output_filename:
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        output_filename = f"english_courses_{timestamp}.json"
    
    output_path = os.path.join(current_dir, "..", "courses", output_filename)
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    
    processor.export_to_flutter_format(valid_courses, output_path)
    
    print(f"\n✓ Exported {len(valid_courses)} courses to: {output_path}")
    
    return valid_courses, output_path


def display_sample_courses(courses: List[Dict], count: int = 5):
    """Display sample courses"""
    print(f"\n{'='*60}")
    print(f"SAMPLE COURSES (showing {min(count, len(courses))} of {len(courses)})")
    print("="*60)
    
    for idx, course in enumerate(courses[:count], 1):
        print(f"\n{idx}. {course['title']}")
        print(f"   Level: {course['level']}")
        print(f"   Category: {course.get('category', 'N/A')}")
        print(f"   Lessons: {course.get('lessonsCount', 0)}")
        print(f"   Duration: {course.get('duration', 'N/A')}")
        print(f"   Rating: {course.get('rating', 0.0)}/5.0")
        print(f"   Description: {course['description'][:100]}...")


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description='Crawl English language courses from public sources',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Crawl all BBC Learning English courses
  python main.py --source bbc
  
  # Crawl only 5 courses (for testing)
  python main.py --source bbc --limit 5
  
  # Crawl and specify custom output filename
  python main.py --source bbc --output my_courses.json
  
  # Crawl all sources
  python main.py --source all
        """
    )
    
    parser.add_argument(
        '--source',
        choices=['bbc', 'all'],
        default='bbc',
        help='Source to crawl (default: bbc)'
    )
    
    parser.add_argument(
        '--limit',
        type=int,
        default=None,
        help='Limit number of courses to crawl (for testing)'
    )
    
    parser.add_argument(
        '--output',
        type=str,
        default=None,
        help='Output filename (default: auto-generated with timestamp)'
    )
    
    parser.add_argument(
        '--no-export',
        action='store_true',
        help='Skip export step (for testing crawlers only)'
    )
    
    parser.add_argument(
        '--sample',
        type=int,
        default=5,
        help='Number of sample courses to display (default: 5)'
    )
    
    args = parser.parse_args()
    
    print("\n" + "="*60)
    print("ENGLISH COURSE CRAWLER")
    print("LexiLingo App - Course Data Collection")
    print("="*60)
    print(f"Started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    # Collect courses from all sources
    all_courses = []
    
    if args.source == 'bbc' or args.source == 'all':
        bbc_courses = crawl_bbc(limit=args.limit)
        all_courses.extend(bbc_courses)
    
    # More sources can be added here
    # if args.source == 'engvid' or args.source == 'all':
    #     engvid_courses = crawl_engvid(limit=args.limit)
    #     all_courses.extend(engvid_courses)
    
    if not all_courses:
        print("\nNo courses were crawled!")
        return 1
    
    # Process and export
    if not args.no_export:
        valid_courses, output_path = process_and_export(all_courses, args.output)
        
        # Display sample courses
        display_sample_courses(valid_courses, args.sample)
        
        print(f"\n{'='*60}")
        print("✓ CRAWLING COMPLETE")
        print("="*60)
        print(f"Total courses collected: {len(valid_courses)}")
        print(f"Output file: {output_path}")
    else:
        print("\n⚠ Export skipped (--no-export flag set)")
        display_sample_courses(all_courses, args.sample)
    
    print(f"\nCompleted at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n\nInterrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n\nError: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
