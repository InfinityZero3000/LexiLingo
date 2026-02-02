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
