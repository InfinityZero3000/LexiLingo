"""
LexiLingo Agent Skills Index

This module provides programmatic access to skill metadata
for AI agents and tools.
"""

SKILLS = {
    'language-learning-patterns': {
        'name': 'Language Learning Patterns',
        'version': '1.0.0',
        'description': 'Best practices for building effective language learning features',
        'categories': [
            'Spaced Repetition',
            'Content Generation',
            'Progress Tracking',
            'Adaptive Learning',
            'Pronunciation',
            'Gamification',
            'Accessibility'
        ],
        'rules': 6,
        'path': 'skills/language-learning-patterns'
    },
    'speech-processing-best-practices': {
        'name': 'Speech Processing Best Practices',
        'version': '1.0.0',
        'description': 'Technical guidelines for speech-to-text and text-to-speech',
        'categories': [
            'Audio Quality',
            'STT Optimization',
            'TTS Implementation',
            'Pronunciation',
            'Performance',
            'Error Handling'
        ],
        'rules': 3,
        'path': 'skills/speech-processing-best-practices'
    },
    'flutter-clean-architecture': {
        'name': 'Flutter Clean Architecture',
        'version': '1.0.0',
        'description': 'Domain/Data/Presentation layer patterns for all Flutter features',
        'categories': [
            'Domain Layer',
            'Data Layer',
            'Presentation Layer',
            'Error Handling'
        ],
        'rules': 5,
        'path': 'skills/flutter-clean-architecture'
    },
    'flutter-ui-animations': {
        'name': 'Flutter UI Animations',
        'version': '1.0.0',
        'description': '60fps animation patterns: shimmer, staggered lists, Hero transitions, Level-Up dialog',
        'categories': [
            'Loading States',
            'List Animation',
            'Navigation',
            'Celebration',
            'Performance'
        ],
        'rules': 4,
        'path': 'skills/flutter-ui-animations'
    },
    'fastapi-lexilingo-endpoints': {
        'name': 'FastAPI LexiLingo Endpoints',
        'version': '1.0.0',
        'description': 'ApiResponse[T] envelope, Pydantic v2, async SQLAlchemy queries, Alembic migrations',
        'categories': [
            'Route Pattern',
            'Schema Pattern',
            'Query Pattern',
            'Migration Pattern'
        ],
        'rules': 3,
        'path': 'skills/fastapi-lexilingo-endpoints'
    },
    'flutter-notification-system': {
        'name': 'Flutter Notification System',
        'version': '1.0.0',
        'description': 'FCM integration gaps: background handler, token registration, foreground display, swipe-to-delete',
        'categories': [
            'FCM Setup',
            'Token Registration',
            'Local Notifications',
            'UI Patterns'
        ],
        'rules': 4,
        'path': 'skills/flutter-notification-system'
    }
}

def get_skill_list():
    """Get list of all available skills"""
    return list(SKILLS.keys())

def get_skill_info(skill_name):
    """Get information about a specific skill"""
    return SKILLS.get(skill_name)

def get_all_skills():
    """Get all skill metadata"""
    return SKILLS

if __name__ == '__main__':
    # Print skill summary
    print("📚 LexiLingo Agent Skills\n")
    for skill_id, info in SKILLS.items():
        print(f"• {info['name']} (v{info['version']})")
        print(f"  {info['description']}")
        print(f"  {info['rules']} rules across {len(info['categories'])} categories")
        print()
