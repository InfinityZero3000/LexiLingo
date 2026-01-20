# English Course Data Crawler

A Python-based web crawler system for collecting publicly available English learning course data to serve as the core dataset for the LexiLingo app.

## 📋 Overview

This crawler system collects course information from reputable free English learning websites, validates the data, and exports it in a format compatible with the LexiLingo Flutter app's Course model.

## 🎯 Features

- **Multi-source Support**: Crawl from BBC Learning English (more sources can be added)
- **Rate Limiting**: Respects server load with configurable delays
- **Robots.txt Compliance**: Checks and respects robots.txt rules
- **Data Validation**: Validates courses against schema and business rules
- **Deduplication**: Automatically removes duplicate courses
- **Error Handling**: Robust retry logic and error recovery
- **Logging**: Comprehensive logging for debugging and monitoring
- **Flutter Compatible**: Exports data in format matching Course entity

## 🚀 Quick Start

### 1. Install Dependencies

```bash
cd data/crawler
pip install -r requirements.txt
```

### 2. Run the Crawler

```bash
# Crawl all BBC Learning English courses
python main.py --source bbc

# Crawl only 5 courses (for testing)
python main.py --source bbc --limit 5

# Specify custom output filename
python main.py --source bbc --output my_courses.json
```

### 3. Output

The crawler will:
- Collect course data from the specified source
- Validate and process the data
- Export to JSON file in `data/courses/`
- Display summary statistics and sample courses

## 📁 Project Structure

```
data/crawler/
├── main.py                    # Main entry point
├── course_crawler.py          # Base crawler class
├── data_processor.py          # Data validation and processing
├── config.yaml                # Configuration file
├── requirements.txt           # Python dependencies
├── .env.example              # Environment template
│
├── sources/                   # Source-specific crawlers
│   └── bbc_learning_english_crawler.py
│
└── logs/                      # Crawler logs (auto-created)

data/courses/                  # Exported course data (auto-created)
data/raw/                      # Raw HTML/JSON data (auto-created)
```

## 🔧 Configuration

Edit `config.yaml` to customize:

- **Rate Limiting**: Adjust delay between requests
- **Data Sources**: Enable/disable sources, configure URLs
- **Validation Rules**: Set min/max lengths, valid levels
- **Output Paths**: Change where data is saved

Example:

```yaml
global:
  rate_limit_seconds: 2
  max_retries: 3
  timeout_seconds: 30

sources:
  bbc_learning_english:
    enabled: true
    rate_limit_seconds: 3
```

## 📊 Data Schema

Each course is exported with the following fields:

```json
{
  "title": "Course Title",
  "description": "Detailed course description",
  "level": "Intermediate",
  "category": "Business English",
  "imageUrl": "https://example.com/image.jpg",
  "duration": "2 hours",
  "lessonsCount": 12,
  "isFeatured": false,
  "rating": 4.5,
  "enrolledCount": 0,
  "createdAt": "2026-01-18T20:00:00Z",
  "updatedAt": "2026-01-18T20:00:00Z"
}
```

### Valid Levels

- Beginner
- Elementary
- Pre-Intermediate
- Intermediate
- Upper-Intermediate
- Advanced

## 🌐 Data Sources

### BBC Learning English

**Status**: Implemented

**URL**: https://www.bbc.co.uk/learningenglish

**Courses Collected**:
- English at Work (Business English)
- 6 Minute English (Listening)
- English in a Minute (Quick Lessons)
- The English We Speak (Vocabulary)
- Grammar courses (Multiple levels)
- And more...

**Notes**: 
- High-quality, professionally produced content
- Structured courses with clear levels
- Rate limit set to 3 seconds to be respectful

### Future Sources

Additional sources can be easily added:
- EngVid.com
- British Council Learn English
- Coursera (public catalog)
- EdX (open courses)

## 🛠️ Adding New Data Sources

To add a new source:

1. **Create a new crawler class** in `sources/`:

```python
from course_crawler import BaseCrawler

class NewSourceCrawler(BaseCrawler):
    def __init__(self):
        super().__init__()
        # Your initialization
    
    def crawl(self, limit=None):
        # Your crawling logic
        courses = []
        # ... collect courses
        return courses
```

2. **Add source configuration** in `config.yaml`:

```yaml
sources:
  new_source:
    enabled: true
    base_url: "https://example.com"
    rate_limit_seconds: 2
```

3. **Import and use** in `main.py`:

```python
from sources.new_source_crawler import NewSourceCrawler

if args.source == 'newsource' or args.source == 'all':
    crawler = NewSourceCrawler()
    courses = crawler.crawl(limit=args.limit)
    all_courses.extend(courses)
```

## 📝 Command Line Options

```bash
python main.py --help

Options:
  --source {bbc,all}    Source to crawl (default: bbc)
  --limit INT          Limit number of courses (for testing)
  --output FILE        Custom output filename
  --no-export          Skip export (testing only)
  --sample INT         Number of sample courses to display
```

## 🔍 Validation Rules

The processor validates each course for:

- Required fields (title, description, level)
- Title length (5-200 characters)
- Description length (20-2000 characters)
- Valid level (from predefined list)
- Valid rating (0-5)
- Non-negative lesson count
- No duplicates

Invalid courses are logged and excluded from export.

## 📈 Usage Examples

### Example 1: Test with Limited Data

```bash
# Test with just 3 courses to verify setup
python main.py --source bbc --limit 3 --sample 3
```

### Example 2: Full BBC Crawl

```bash
# Collect all BBC Learning English courses
python main.py --source bbc
```

### Example 3: Custom Export

```bash
# Export to specific filename
python main.py --source bbc --output bbc_courses_2026.json
```

### Example 4: Crawl Multiple Sources

```bash
# When more sources are added
python main.py --source all
```

## 🐛 Troubleshooting

### Issue: ImportError or Module Not Found

**Solution**: Make sure you're in the correct directory and dependencies are installed:
```bash
cd data/crawler
pip install -r requirements.txt
python main.py --source bbc --limit 3
```

### Issue: Connection Timeout

**Solution**: Increase timeout in `config.yaml`:
```yaml
global:
  timeout_seconds: 60
```

### Issue: Too Many Requests / Rate Limiting

**Solution**: Increase rate limit delay in `config.yaml`:
```yaml
sources:
  bbc_learning_english:
    rate_limit_seconds: 5  # Increase from 3 to 5 seconds
```

### Issue: Validation Errors

**Solution**: Check the logs in `data/crawler/logs/` for detailed error messages. Common issues:
- Description too short (needs at least 20 characters)
- Invalid level (must be one of the predefined levels)

## 📊 Output Example

```
============================================================
ENGLISH COURSE CRAWLER
LexiLingo App - Course Data Collection
============================================================
Started at: 2026-01-18 20:00:00

============================================================
BBC LEARNING ENGLISH CRAWLER
============================================================
✓ Crawled 12 courses from BBC Learning English

============================================================
PROCESSING AND VALIDATING DATA
============================================================

📊 Processing Statistics:
   Total courses: 12
   ✓ Valid: 12
   ✗ Invalid: 0
   ⚠ Duplicates: 0

✓ Exported 12 courses to: data/courses/english_courses_20260118_200000.json

============================================================
SAMPLE COURSES (showing 5 of 12)
============================================================

1. English at Work
   Level: Intermediate
   Category: Business English
   Lessons: 12
   Duration: 2 hours
   Rating: 4.5/5.0
   Description: Learn useful business English phrases and improve your workplace...

...
```

## 🔒 Legal & Ethical Considerations

- Only crawls **publicly accessible** content
- Respects `robots.txt` for each website
- Implements **rate limiting** to avoid server overload
- Stores data for **educational purposes** in LexiLingo app
- ⚠️ Ensure you have the right to use this data in your application
- ⚠️ Some sources may require attribution - check terms of service

## 🔄 Importing Data to Flutter App

After crawling, you can import the data into your Flutter app:

1. **Option A: Direct SQLite Import**
   - Place JSON file in assets
   - Load and insert into SQLite on first app launch

2. **Option B: Seed Data**
   - Include JSON in app bundle
   - Import via `CourseLocalDataSource`

Example import code:

```dart
// In your Flutter app
Future<void> importCourses() async {
  final jsonString = await rootBundle.loadString('assets/courses.json');
  final List<dynamic> jsonData = json.decode(jsonString);
  
  for (var courseJson in jsonData) {
    final course = CourseModel.fromJson(courseJson);
    await courseLocalDataSource.insertCourse(course);
  }
}
```

## 📞 Support

For issues or questions:
- Check logs in `data/crawler/logs/`
- Review error messages in console output
- Verify configuration in `config.yaml`
- Test with `--limit 3` for quick debugging

## 🎯 Next Steps

1. Run the crawler to collect BBC Learning English courses
2. 🔄 Review the output JSON file
3. 📱 Import data into Flutter app
4. 🌟 Add more data sources as needed
5. 🔄 Run periodically to update course catalog

---

**Happy Crawling! 🚀**
