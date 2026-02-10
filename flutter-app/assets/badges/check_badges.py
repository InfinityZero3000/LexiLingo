#!/usr/bin/env python3
"""
Badge Status Generator
Creates a visual report of badge completions and missing files.
"""

import os
from pathlib import Path

# Badge categories and their files
BADGE_STRUCTURE = {
    "Lesson Badges": [
        "common-lesson.png",
        "rare-lesson.png",
        "epic-lesson.png",
        "legendary-lesson.png"
    ],
    "Vocabulary Badges": [
        "common-vocabulary.png",
        "rare-vocabulary.png",
        "epic-vocabulary.png",
        "legendary-vocabulary.png"
    ],
    "Streak Badges": [
        "streak3.png",
        "streak7.png",
        "streak14.png", 
        "streak30.png",
        "streak90.png",
        "streak365.png"
    ],

    "Perfect Score": [
        "100%.png",
        "first-perfect.png",
        "perfect-10.png",
        "perfect-50.png",
        "quiz-champion.png"
    ],
    "Level Milestones": [
        "lv25.png",
        "lv50.png",
        "lv100.png",
        "lv150.png",
        "lv200.png",
        "lv300.png",
        "lv500.png"
    ],
    "Course & Voice": [
        "course-graduate.png",
        "course-master.png",
        "voice-starter.png",
        "voice-pro.png",
        "pronunciation-pro.png"
    ],
    "Special": [
        "moon.png",
        "early-bird.png",
        "speed-demon.png",
        "challenge-crusher.png",
        "milestone-maker.png",
        "comeback-king.png"
    ],
    "Skills": [
        "grammar-guardian.png",
        "culture-explorer.png",
        "writing-wizard.png",
        "listening-legend.png"
    ],
    "Social": [
        "social-butterfly.png",
        "conversation-champion.png",
        "feedback-friend.png"
    ]
}

def check_badge_files(badges_dir: Path):
    """Check which badge files exist."""
    total = 0
    existing = 0
    missing = []
    
    print("LexiLingo Badge Status Report\n")
    print("=" * 60)
    
    for category, files in BADGE_STRUCTURE.items():
        print(f"\n📁 {category}")
        print("-" * 60)
        
        category_existing = 0
        category_missing = []
        
        for filename in files:
            total += 1
            filepath = badges_dir / filename
            
            if filepath.exists():
                existing += 1
                category_existing += 1
                print(f"  ✅ {filename}")
            else:
                missing.append(filename)
                category_missing.append(filename)
                print(f"  ❌ {filename} - MISSING")
        
        print(f"\n  Status: {category_existing}/{len(files)} files exist")
        
        if category_missing:
            print(f"  Missing: {', '.join(category_missing)}")
    
    print("\n" + "=" * 60)
    print(f"\n📊 SUMMARY")
    print(f"  Total badges: {total}")
    print(f"  Existing: {existing} ✅")
    print(f"  Missing: {len(missing)} ❌")
    print(f"  Completion: {(existing/total)*100:.1f}%")
    
    if missing:
        print(f"\n❌ Missing Badges ({len(missing)}):")
        for i, filename in enumerate(missing, 1):
            print(f"  {i}. {filename}")
    
    print("\n" + "=" * 60)
    return missing

def main():
    # Get script directory
    script_dir = Path(__file__).parent.absolute()
    
    print(f"📂 Badge directory: {script_dir}\n")
    
    # Check badge files
    missing = check_badge_files(script_dir)
    
    if not missing:
        print("\n🎉 All badges are present!")
    else:
        print(f"\n⚠️  Action Required: Generate {len(missing)} missing badge files")
        print(f"   See MISSING_BADGES.md for generation prompts")
    
    print(f"\n🔍 Open badge-viewer.html to view badges in large size")
    print(f"   File location: {script_dir}/badge-viewer.html")

if __name__ == "__main__":
    main()
