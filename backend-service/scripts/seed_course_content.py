"""
Comprehensive Course Content Seed Script
=========================================
Seeds course categories, lesson content with exercises, vocabulary, and tests.

Run: python -m scripts.seed_course_content

Flow:
1. Collect/Generate Data
2. Process and validate
3. Import to PostgreSQL database
4. Ready for Flutter UI display
5. Users can learn and gain XP/skills

Author: LexiLingo Team
"""

import sys
import os
from pathlib import Path

# Add backend-service to path
backend_path = Path(__file__).parent.parent
sys.path.insert(0, str(backend_path))

import uuid
import asyncio
from datetime import datetime
from sqlalchemy import text, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import AsyncSessionLocal, engine
from app.models.course import Course, Unit, Lesson
from app.models.course_category import CourseCategory
from app.models.vocabulary import VocabularyItem, PartOfSpeech, DifficultyLevel


# ==========================================
# 1. COURSE CATEGORIES DATA
# ==========================================
COURSE_CATEGORIES = [
    {
        "name": "Grammar",
        "slug": "grammar",
        "description": "Learn English grammar rules, from basic to advanced structures",
        "icon": "menu_book",
        "color": "#4CAF50",
        "order_index": 1,
    },
    {
        "name": "Vocabulary",
        "slug": "vocabulary", 
        "description": "Expand your English vocabulary with thematic word lists",
        "icon": "abc",
        "color": "#2196F3",
        "order_index": 2,
    },
    {
        "name": "Conversation",
        "slug": "conversation",
        "description": "Practice real-world English conversations and dialogues",
        "icon": "chat",
        "color": "#FF9800",
        "order_index": 3,
    },
    {
        "name": "Business English",
        "slug": "business",
        "description": "Professional English for workplace and career success",
        "icon": "business",
        "color": "#9C27B0",
        "order_index": 4,
    },
    {
        "name": "Travel English",
        "slug": "travel",
        "description": "Essential English phrases for travelers and tourists",
        "icon": "flight",
        "color": "#E91E63",
        "order_index": 5,
    },
    {
        "name": "Test Prep",
        "slug": "test-prep",
        "description": "Prepare for IELTS, TOEFL, TOEIC and other English tests",
        "icon": "quiz",
        "color": "#607D8B",
        "order_index": 6,
    },
]


# ==========================================
# 2. LESSON CONTENT DATA (With Exercises)
# ==========================================
LESSON_CONTENTS = {
    "Hello & Greetings": {
        "introduction": "Learn how to greet people in different situations. Greetings are essential for starting conversations in English!",
        "vocabulary": [
            {"word": "Hello", "translation": "Xin chào", "example": "Hello, how are you?", "audio_url": None},
            {"word": "Hi", "translation": "Chào (thân mật)", "example": "Hi there!", "audio_url": None},
            {"word": "Good morning", "translation": "Chào buổi sáng", "example": "Good morning, everyone!", "audio_url": None},
            {"word": "Good afternoon", "translation": "Chào buổi chiều", "example": "Good afternoon, Mr. Smith.", "audio_url": None},
            {"word": "Good evening", "translation": "Chào buổi tối", "example": "Good evening, welcome to the party.", "audio_url": None},
            {"word": "Goodbye", "translation": "Tạm biệt", "example": "Goodbye, see you tomorrow!", "audio_url": None},
        ],
        "grammar_notes": [
            "Use 'Good morning' before 12 PM",
            "Use 'Good afternoon' from 12 PM to 6 PM", 
            "Use 'Good evening' after 6 PM",
            "'Hi' is informal, 'Hello' can be used in any situation"
        ],
        "exercises": [
            {
                "type": "multiple_choice",
                "question": "What do you say when you meet someone in the morning?",
                "options": ["Good evening", "Good morning", "Goodbye", "Good night"],
                "correct_answer": 1,
                "explanation": "We use 'Good morning' to greet someone before noon.",
                "xp_reward": 5,
                "skill": "vocabulary"
            },
            {
                "type": "multiple_choice",
                "question": "Which greeting is more informal?",
                "options": ["Hello", "Good afternoon", "Hi", "Good evening"],
                "correct_answer": 2,
                "explanation": "'Hi' is the most informal greeting among these options.",
                "xp_reward": 5,
                "skill": "vocabulary"
            },
            {
                "type": "fill_blank",
                "question": "Complete: 'Good _____, nice to meet you.' (afternoon greeting)",
                "correct_answer": "afternoon",
                "hint": "Used between 12 PM and 6 PM",
                "xp_reward": 10,
                "skill": "vocabulary"
            },
            {
                "type": "matching",
                "question": "Match the greetings with their Vietnamese translation",
                "pairs": [
                    {"english": "Hello", "vietnamese": "Xin chào"},
                    {"english": "Goodbye", "vietnamese": "Tạm biệt"},
                    {"english": "Good morning", "vietnamese": "Chào buổi sáng"},
                ],
                "xp_reward": 15,
                "skill": "vocabulary"
            },
            {
                "type": "listening",
                "question": "Listen and choose the correct greeting",
                "audio_text": "Good afternoon, welcome to our office!",
                "options": ["Good morning", "Good afternoon", "Good evening", "Hello"],
                "correct_answer": 1,
                "xp_reward": 10,
                "skill": "listening"
            }
        ]
    },
    
    "Introducing Yourself": {
        "introduction": "Learn how to introduce yourself and talk about basic personal information in English.",
        "vocabulary": [
            {"word": "My name is...", "translation": "Tên tôi là...", "example": "My name is John.", "audio_url": None},
            {"word": "Nice to meet you", "translation": "Rất vui được gặp bạn", "example": "Nice to meet you, Sarah!", "audio_url": None},
            {"word": "I am from...", "translation": "Tôi đến từ...", "example": "I am from Vietnam.", "audio_url": None},
            {"word": "I live in...", "translation": "Tôi sống ở...", "example": "I live in Ho Chi Minh City.", "audio_url": None},
            {"word": "I work as...", "translation": "Tôi làm việc như là...", "example": "I work as a teacher.", "audio_url": None},
            {"word": "I am ... years old", "translation": "Tôi ... tuổi", "example": "I am 25 years old.", "audio_url": None},
        ],
        "grammar_notes": [
            "Use 'I am' or 'I'm' for introducing yourself",
            "Use 'My name is' or 'I'm called' to tell your name",
            "Use 'from' for nationality/origin and 'in' for current location"
        ],
        "exercises": [
            {
                "type": "multiple_choice",
                "question": "How do you ask someone's name politely?",
                "options": ["You name?", "What is your name?", "Name you?", "Your name what?"],
                "correct_answer": 1,
                "explanation": "'What is your name?' is the correct and polite way to ask.",
                "xp_reward": 5,
                "skill": "grammar"
            },
            {
                "type": "fill_blank",
                "question": "Complete: 'Hello, my _____ is Anna.'",
                "correct_answer": "name",
                "hint": "What you are called",
                "xp_reward": 10,
                "skill": "vocabulary"
            },
            {
                "type": "reorder",
                "question": "Put the words in correct order: 'meet / Nice / you / to'",
                "correct_order": ["Nice", "to", "meet", "you"],
                "xp_reward": 10,
                "skill": "grammar"
            },
            {
                "type": "multiple_choice",
                "question": "I _____ from Vietnam.",
                "options": ["is", "am", "are", "be"],
                "correct_answer": 1,
                "explanation": "Use 'am' with 'I' (first person singular).",
                "xp_reward": 5,
                "skill": "grammar"
            },
            {
                "type": "speaking",
                "question": "Introduce yourself: Say your name, where you're from, and your age.",
                "example_answer": "Hi, my name is [Name]. I am from [Country]. I am [Age] years old.",
                "xp_reward": 20,
                "skill": "speaking"
            },
            {
                "type": "fill_blank",
                "question": "Complete: 'I _____ in New York. (currently residing)'",
                "correct_answer": "live",
                "hint": "Verb for where you stay/reside",
                "xp_reward": 10,
                "skill": "vocabulary"
            },
            {
                "type": "translation",
                "question": "Translate to English: 'Rất vui được gặp bạn'",
                "correct_answer": "Nice to meet you",
                "alternatives": ["nice to meet you", "pleased to meet you", "glad to meet you"],
                "xp_reward": 10,
                "skill": "vocabulary"
            }
        ]
    },

    "Numbers 1-20": {
        "introduction": "Master numbers 1-20 in English. Numbers are essential for everyday conversations!",
        "vocabulary": [
            {"word": "One", "translation": "Một", "example": "I have one apple.", "audio_url": None},
            {"word": "Two", "translation": "Hai", "example": "There are two cats.", "audio_url": None},
            {"word": "Three", "translation": "Ba", "example": "I need three books.", "audio_url": None},
            {"word": "Four", "translation": "Bốn", "example": "The table has four legs.", "audio_url": None},
            {"word": "Five", "translation": "Năm", "example": "I have five fingers.", "audio_url": None},
            {"word": "Ten", "translation": "Mười", "example": "Count to ten.", "audio_url": None},
            {"word": "Eleven", "translation": "Mười một", "example": "She is eleven years old.", "audio_url": None},
            {"word": "Fifteen", "translation": "Mười lăm", "example": "The class starts in fifteen minutes.", "audio_url": None},
            {"word": "Twenty", "translation": "Hai mươi", "example": "I saved twenty dollars.", "audio_url": None},
        ],
        "grammar_notes": [
            "Numbers 1-12 have unique names",
            "Numbers 13-19 end with '-teen' (thirteen, fourteen...)",
            "Multiples of 10 end with '-ty' (twenty, thirty...)"
        ],
        "exercises": [
            {
                "type": "multiple_choice",
                "question": "What number comes after eleven?",
                "options": ["Ten", "Twelve", "Thirteen", "Twenty"],
                "correct_answer": 1,
                "explanation": "Twelve (12) comes after eleven (11).",
                "xp_reward": 5,
                "skill": "vocabulary"
            },
            {
                "type": "fill_blank",
                "question": "Write the number in words: 15 = _____",
                "correct_answer": "fifteen",
                "hint": "5 + 10 = ?",
                "xp_reward": 10,
                "skill": "vocabulary"
            },
            {
                "type": "matching",
                "question": "Match numbers with words",
                "pairs": [
                    {"number": "7", "word": "seven"},
                    {"number": "13", "word": "thirteen"},
                    {"number": "20", "word": "twenty"},
                    {"number": "18", "word": "eighteen"},
                ],
                "xp_reward": 15,
                "skill": "vocabulary"
            },
            {
                "type": "listening",
                "question": "Listen and type the number you hear",
                "audio_text": "sixteen",
                "correct_answer": "16",
                "alternatives": ["sixteen", "Sixteen"],
                "xp_reward": 10,
                "skill": "listening"
            },
            {
                "type": "multiple_choice",
                "question": "3 + 4 = ?",
                "options": ["Six", "Seven", "Eight", "Nine"],
                "correct_answer": 1,
                "explanation": "Three plus four equals seven.",
                "xp_reward": 5,
                "skill": "vocabulary"
            },
            {
                "type": "translation",
                "question": "Translate: 'Mười hai'",
                "correct_answer": "Twelve",
                "alternatives": ["twelve", "TWELVE"],
                "xp_reward": 10,
                "skill": "vocabulary"
            }
        ]
    },

    "Colors": {
        "introduction": "Learn the names of common colors in English. Colors are used everywhere in daily life!",
        "vocabulary": [
            {"word": "Red", "translation": "Đỏ", "example": "The apple is red.", "audio_url": None},
            {"word": "Blue", "translation": "Xanh dương", "example": "The sky is blue.", "audio_url": None},
            {"word": "Green", "translation": "Xanh lá", "example": "The grass is green.", "audio_url": None},
            {"word": "Yellow", "translation": "Vàng", "example": "The sun is yellow.", "audio_url": None},
            {"word": "Orange", "translation": "Cam", "example": "I like orange juice.", "audio_url": None},
            {"word": "Purple", "translation": "Tím", "example": "Purple is a royal color.", "audio_url": None},
            {"word": "Black", "translation": "Đen", "example": "I have a black cat.", "audio_url": None},
            {"word": "White", "translation": "Trắng", "example": "Snow is white.", "audio_url": None},
        ],
        "grammar_notes": [
            "Colors are adjectives and come before nouns: 'a red apple'",
            "Colors can also be nouns: 'My favorite color is blue'",
            "Some colors have shades: light blue, dark green"
        ],
        "exercises": [
            {
                "type": "multiple_choice",
                "question": "What color is the sky on a clear day?",
                "options": ["Red", "Green", "Blue", "Yellow"],
                "correct_answer": 2,
                "explanation": "The sky appears blue on a clear day.",
                "xp_reward": 5,
                "skill": "vocabulary"
            },
            {
                "type": "matching",
                "question": "Match colors with objects",
                "pairs": [
                    {"object": "Grass", "color": "Green"},
                    {"object": "Sun", "color": "Yellow"},
                    {"object": "Night", "color": "Black"},
                    {"object": "Snow", "color": "White"},
                ],
                "xp_reward": 15,
                "skill": "vocabulary"
            },
            {
                "type": "fill_blank",
                "question": "The banana is _____. (color)",
                "correct_answer": "yellow",
                "hint": "The color of sunshine",
                "xp_reward": 10,
                "skill": "vocabulary"
            },
            {
                "type": "translation",
                "question": "Translate: 'Xanh lá'",
                "correct_answer": "Green",
                "alternatives": ["green", "GREEN"],
                "xp_reward": 10,
                "skill": "vocabulary"
            },
            {
                "type": "multiple_choice",
                "question": "Mix red and blue. What color do you get?",
                "options": ["Green", "Orange", "Purple", "Yellow"],
                "correct_answer": 2,
                "explanation": "Red + Blue = Purple",
                "xp_reward": 5,
                "skill": "vocabulary"
            }
        ]
    },

    "Email Etiquette": {
        "introduction": "Master professional email writing for business communication. Learn formal greetings, closings, and proper tone.",
        "vocabulary": [
            {"word": "Dear Mr./Ms.", "translation": "Kính gửi ông/bà", "example": "Dear Mr. Smith,", "audio_url": None},
            {"word": "I am writing to...", "translation": "Tôi viết thư này để...", "example": "I am writing to inquire about...", "audio_url": None},
            {"word": "Please find attached", "translation": "Vui lòng xem file đính kèm", "example": "Please find attached the report.", "audio_url": None},
            {"word": "Best regards", "translation": "Trân trọng", "example": "Best regards, John", "audio_url": None},
            {"word": "Looking forward to", "translation": "Mong đợi", "example": "Looking forward to your reply.", "audio_url": None},
            {"word": "As per our discussion", "translation": "Theo như cuộc thảo luận", "example": "As per our discussion yesterday...", "audio_url": None},
        ],
        "grammar_notes": [
            "Always start with a proper greeting",
            "Keep emails concise and professional",
            "Use 'Best regards' or 'Kind regards' to close formal emails",
            "Avoid using casual language like 'Hey' in business emails"
        ],
        "exercises": [
            {
                "type": "multiple_choice",
                "question": "Which is the most appropriate greeting for a business email?",
                "options": ["Hey!", "Dear Mr. Johnson,", "Yo!", "What's up?"],
                "correct_answer": 1,
                "explanation": "'Dear Mr./Ms.' is the standard formal greeting for business emails.",
                "xp_reward": 5,
                "skill": "vocabulary"
            },
            {
                "type": "multiple_choice",
                "question": "Which closing is appropriate for a formal email?",
                "options": ["Later!", "XOXO", "Best regards,", "Bye bye!"],
                "correct_answer": 2,
                "explanation": "'Best regards' is a professional email closing.",
                "xp_reward": 5,
                "skill": "vocabulary"
            },
            {
                "type": "fill_blank",
                "question": "Complete: 'I am _____ to inquire about your services.'",
                "correct_answer": "writing",
                "hint": "The action of creating an email",
                "xp_reward": 10,
                "skill": "grammar"
            },
            {
                "type": "reorder",
                "question": "Order the email parts correctly",
                "items": ["Greeting", "Body", "Closing", "Subject line"],
                "correct_order": ["Subject line", "Greeting", "Body", "Closing"],
                "xp_reward": 15,
                "skill": "writing"
            },
            {
                "type": "multiple_choice",
                "question": "'Please find attached' is used when you...",
                "options": ["Want to meet someone", "Send a file with the email", "Ask for information", "End the email"],
                "correct_answer": 1,
                "explanation": "This phrase indicates you've attached a file to the email.",
                "xp_reward": 5,
                "skill": "vocabulary"
            },
            {
                "type": "writing",
                "question": "Write a short email requesting a meeting with your manager.",
                "requirements": ["Include proper greeting", "State the purpose", "Suggest a time", "Use formal closing"],
                "example_answer": "Dear Mr. Smith,\n\nI am writing to request a meeting to discuss the project progress. Would you be available on Friday at 2 PM?\n\nBest regards,\n[Your name]",
                "xp_reward": 25,
                "skill": "writing"
            },
            {
                "type": "fill_blank",
                "question": "Complete: 'Looking _____ to hearing from you.'",
                "correct_answer": "forward",
                "hint": "Expecting/anticipating",
                "xp_reward": 10,
                "skill": "grammar"
            },
            {
                "type": "translation",
                "question": "Translate: 'Trân trọng' (email closing)",
                "correct_answer": "Best regards",
                "alternatives": ["Kind regards", "Sincerely", "Yours sincerely"],
                "xp_reward": 10,
                "skill": "vocabulary"
            }
        ]
    },

    "Phone Conversations": {
        "introduction": "Learn how to handle professional phone calls with confidence. Master common phrases for business calls.",
        "vocabulary": [
            {"word": "May I speak to...", "translation": "Tôi có thể nói chuyện với...", "example": "May I speak to Mr. Brown?", "audio_url": None},
            {"word": "This is ... speaking", "translation": "Tôi là ... đang nói", "example": "This is John speaking.", "audio_url": None},
            {"word": "Please hold", "translation": "Xin vui lòng chờ", "example": "Please hold, I'll transfer your call.", "audio_url": None},
            {"word": "Could you repeat that?", "translation": "Bạn có thể nhắc lại không?", "example": "I'm sorry, could you repeat that?", "audio_url": None},
            {"word": "I'll call you back", "translation": "Tôi sẽ gọi lại cho bạn", "example": "I'll call you back in 10 minutes.", "audio_url": None},
            {"word": "Leave a message", "translation": "Để lại lời nhắn", "example": "Would you like to leave a message?", "audio_url": None},
        ],
        "grammar_notes": [
            "Always identify yourself when answering: 'This is [Name] speaking'",
            "Use 'May I' or 'Could I' for polite requests",
            "Use 'Please hold' when putting someone on hold",
            "Say 'I'm sorry' before asking someone to repeat"
        ],
        "exercises": [
            {
                "type": "multiple_choice",
                "question": "How do you politely ask to speak to someone on the phone?",
                "options": ["Give me John!", "I want to talk to John", "May I speak to John, please?", "Where is John?"],
                "correct_answer": 2,
                "explanation": "'May I speak to...' is the polite way to request to speak with someone.",
                "xp_reward": 5,
                "skill": "vocabulary"
            },
            {
                "type": "fill_blank",
                "question": "Complete: 'Hello, this is Sarah _____.'",
                "correct_answer": "speaking",
                "hint": "Verb indicating you're the one talking",
                "xp_reward": 10,
                "skill": "vocabulary"
            },
            {
                "type": "listening",
                "question": "Listen to the phone conversation and answer: What does the caller want?",
                "audio_text": "Good morning. This is ABC Company. May I speak to the marketing manager, please?",
                "options": ["To place an order", "To speak to the marketing manager", "To leave a message", "To cancel a meeting"],
                "correct_answer": 1,
                "xp_reward": 10,
                "skill": "listening"
            },
            {
                "type": "multiple_choice",
                "question": "What do you say when you need the caller to wait?",
                "options": ["Wait!", "Stop talking!", "Please hold.", "Don't hang up!"],
                "correct_answer": 2,
                "explanation": "'Please hold' is the polite way to ask someone to wait on the phone.",
                "xp_reward": 5,
                "skill": "vocabulary"
            },
            {
                "type": "reorder",
                "question": "Order these phone conversation steps",
                "items": ["Say goodbye", "Answer the phone", "Discuss the matter", "Identify yourself"],
                "correct_order": ["Answer the phone", "Identify yourself", "Discuss the matter", "Say goodbye"],
                "xp_reward": 15,
                "skill": "speaking"
            },
            {
                "type": "speaking",
                "question": "Practice: Answer a business call and transfer it to your colleague.",
                "example_answer": "Good morning, ABC Company. This is Sarah speaking. How may I help you? ... Yes, please hold while I transfer your call to Mr. Brown.",
                "xp_reward": 20,
                "skill": "speaking"
            },
            {
                "type": "fill_blank",
                "question": "Complete: 'I'm sorry, could you _____ that? I didn't hear you clearly.'",
                "correct_answer": "repeat",
                "hint": "Say again",
                "xp_reward": 10,
                "skill": "listening"
            },
            {
                "type": "multiple_choice",
                "question": "'I'll call you back' means...",
                "options": ["I will end the call", "I will phone you again later", "I want you to call me", "I'm busy now"],
                "correct_answer": 1,
                "explanation": "This phrase means you will phone the person again at a later time.",
                "xp_reward": 5,
                "skill": "vocabulary"
            },
            {
                "type": "translation",
                "question": "Translate: 'Xin vui lòng chờ'",
                "correct_answer": "Please hold",
                "alternatives": ["please hold", "Please wait"],
                "xp_reward": 10,
                "skill": "vocabulary"
            },
            {
                "type": "multiple_choice",
                "question": "The person you called is not available. What might they say?",
                "options": ["Go away!", "She's here.", "Would you like to leave a message?", "Don't call again."],
                "correct_answer": 2,
                "explanation": "When someone is unavailable, you may be asked to leave a message.",
                "xp_reward": 5,
                "skill": "vocabulary"
            }
        ]
    },

    "Making Reservations": {
        "introduction": "Learn how to make reservations at restaurants, hotels, and other venues in English.",
        "vocabulary": [
            {"word": "I'd like to make a reservation", "translation": "Tôi muốn đặt chỗ", "example": "I'd like to make a reservation for tonight.", "audio_url": None},
            {"word": "For how many people?", "translation": "Cho bao nhiêu người?", "example": "For how many people, sir?", "audio_url": None},
            {"word": "What time?", "translation": "Mấy giờ?", "example": "What time would you like?", "audio_url": None},
            {"word": "Table for two", "translation": "Bàn cho hai người", "example": "A table for two, please.", "audio_url": None},
            {"word": "Fully booked", "translation": "Hết chỗ", "example": "I'm sorry, we're fully booked tonight.", "audio_url": None},
            {"word": "Under the name of", "translation": "Dưới tên", "example": "The reservation is under the name of Smith.", "audio_url": None},
        ],
        "grammar_notes": [
            "Use 'I'd like to' (I would like to) for polite requests",
            "Specify the number of people, date, and time",
            "Give your name for the reservation",
            "'Fully booked' means no tables are available"
        ],
        "exercises": [
            {
                "type": "multiple_choice",
                "question": "How do you start making a reservation at a restaurant?",
                "options": ["Give me a table!", "I want food!", "I'd like to make a reservation, please.", "Food now!"],
                "correct_answer": 2,
                "explanation": "'I'd like to make a reservation' is the polite way to book a table.",
                "xp_reward": 5,
                "skill": "vocabulary"
            },
            {
                "type": "fill_blank",
                "question": "Complete: 'I'd like a table _____ four people, please.'",
                "correct_answer": "for",
                "hint": "Preposition indicating purpose/benefit",
                "xp_reward": 10,
                "skill": "grammar"
            },
            {
                "type": "reorder",
                "question": "Order the reservation conversation",
                "items": ["Give your name", "Confirm the details", "Say you want to make a reservation", "Specify date and time"],
                "correct_order": ["Say you want to make a reservation", "Specify date and time", "Give your name", "Confirm the details"],
                "xp_reward": 15,
                "skill": "speaking"
            },
            {
                "type": "listening",
                "question": "Listen: What is the customer asking for?",
                "audio_text": "Good evening. I'd like to make a reservation for Saturday at 7 PM for 4 people, please.",
                "options": ["Lunch on Friday for 2", "Dinner on Saturday for 4", "Breakfast on Sunday for 3", "Lunch on Monday for 5"],
                "correct_answer": 1,
                "xp_reward": 10,
                "skill": "listening"
            },
            {
                "type": "multiple_choice",
                "question": "The restaurant says 'We're fully booked'. What does this mean?",
                "options": ["They have many books", "All tables are reserved", "They are closing", "Food is finished"],
                "correct_answer": 1,
                "explanation": "'Fully booked' means all reservations are taken and no tables are available.",
                "xp_reward": 5,
                "skill": "vocabulary"
            },
            {
                "type": "speaking",
                "question": "Practice making a reservation: 2 people, Friday evening, 7:30 PM, under your name.",
                "example_answer": "Hello, I'd like to make a reservation for Friday evening, please. For 2 people at 7:30 PM. The reservation is under the name [Your name].",
                "xp_reward": 20,
                "skill": "speaking"
            }
        ]
    },

    "Ordering Food": {
        "introduction": "Learn essential phrases for ordering food and drinks at restaurants.",
        "vocabulary": [
            {"word": "May I take your order?", "translation": "Tôi có thể ghi order chưa?", "example": "Good evening, may I take your order?", "audio_url": None},
            {"word": "I'll have...", "translation": "Tôi sẽ dùng...", "example": "I'll have the steak, please.", "audio_url": None},
            {"word": "What do you recommend?", "translation": "Bạn gợi ý gì?", "example": "What do you recommend for a first-time visitor?", "audio_url": None},
            {"word": "Could I have the bill?", "translation": "Cho tôi xin hóa đơn?", "example": "Excuse me, could I have the bill, please?", "audio_url": None},
            {"word": "Medium rare", "translation": "Tái vừa", "example": "I'd like my steak medium rare.", "audio_url": None},
            {"word": "On the side", "translation": "Để riêng", "example": "Can I have the sauce on the side?", "audio_url": None},
        ],
        "grammar_notes": [
            "Use 'I'll have' to order food",
            "Use 'Could I have' for polite requests",
            "Steak cooking levels: rare, medium rare, medium, medium well, well done",
            "'On the side' means served separately"
        ],
        "exercises": [
            {
                "type": "multiple_choice",
                "question": "How do you politely order food?",
                "options": ["Give me food!", "I'll have the pasta, please.", "Food now!", "I want pasta!"],
                "correct_answer": 1,
                "explanation": "'I'll have..., please' is the polite way to order.",
                "xp_reward": 5,
                "skill": "vocabulary"
            },
            {
                "type": "fill_blank",
                "question": "Complete: 'Could I have the _____, please?' (asking to pay)",
                "correct_answer": "bill",
                "hint": "The piece of paper showing what you owe",
                "xp_reward": 10,
                "skill": "vocabulary"
            },
            {
                "type": "matching",
                "question": "Match steak cooking levels with their descriptions",
                "pairs": [
                    {"level": "Rare", "description": "Very red inside"},
                    {"level": "Medium", "description": "Pink in the center"},
                    {"level": "Well done", "description": "Fully cooked, no pink"},
                ],
                "xp_reward": 15,
                "skill": "vocabulary"
            },
            {
                "type": "listening",
                "question": "Listen to the order. What did the customer order?",
                "audio_text": "I'll have the grilled salmon with a side of vegetables, please.",
                "options": ["Steak with fries", "Grilled salmon with vegetables", "Pasta with salad", "Chicken with rice"],
                "correct_answer": 1,
                "xp_reward": 10,
                "skill": "listening"
            },
            {
                "type": "speaking",
                "question": "Practice ordering: Main course, drink, and dessert.",
                "example_answer": "I'll have the chicken sandwich for my main course. For my drink, I'd like a glass of orange juice. And for dessert, I'll have the chocolate cake, please.",
                "xp_reward": 20,
                "skill": "speaking"
            },
            {
                "type": "multiple_choice",
                "question": "'On the side' means...",
                "options": ["Mixed together", "Served separately", "Very hot", "Without sauce"],
                "correct_answer": 1,
                "explanation": "'On the side' means the item is served separately, not on the main dish.",
                "xp_reward": 5,
                "skill": "vocabulary"
            },
            {
                "type": "fill_blank",
                "question": "Complete: 'What do you _____ for dessert?'",
                "correct_answer": "recommend",
                "hint": "Suggest/advise",
                "xp_reward": 10,
                "skill": "vocabulary"
            },
            {
                "type": "translation",
                "question": "Translate: 'Tái vừa' (steak)",
                "correct_answer": "Medium rare",
                "alternatives": ["medium rare", "medium-rare"],
                "xp_reward": 10,
                "skill": "vocabulary"
            }
        ]
    },

    "Perfect Continuous Tenses": {
        "introduction": "Master the perfect continuous tenses in English: Present Perfect Continuous, Past Perfect Continuous, and Future Perfect Continuous.",
        "vocabulary": [
            {"word": "have/has been + verb-ing", "translation": "đã và đang làm", "example": "I have been studying English for 3 years.", "audio_url": None},
            {"word": "had been + verb-ing", "translation": "đã từng đang làm (quá khứ)", "example": "She had been waiting for an hour before he arrived.", "audio_url": None},
            {"word": "will have been + verb-ing", "translation": "sẽ đã và đang làm", "example": "By next month, I will have been working here for 5 years.", "audio_url": None},
        ],
        "grammar_notes": [
            "Present Perfect Continuous: have/has + been + verb-ing",
            "Emphasizes duration of an action that started in the past and continues to present",
            "Past Perfect Continuous: had + been + verb-ing (action before another past action)",
            "Future Perfect Continuous: will + have + been + verb-ing (duration up to a future point)"
        ],
        "exercises": [
            {
                "type": "multiple_choice",
                "question": "I _____ English for three years.",
                "options": ["study", "am studying", "have been studying", "studied"],
                "correct_answer": 2,
                "explanation": "Present Perfect Continuous is used for actions that started in the past and continue to now with emphasis on duration.",
                "xp_reward": 10,
                "skill": "grammar"
            },
            {
                "type": "fill_blank",
                "question": "Complete: 'She _____ for the bus for 30 minutes when it finally arrived.'",
                "correct_answer": "had been waiting",
                "hint": "Past Perfect Continuous (before another past event)",
                "xp_reward": 15,
                "skill": "grammar"
            },
            {
                "type": "multiple_choice",
                "question": "By December, we _____ in this house for ten years.",
                "options": ["live", "are living", "have lived", "will have been living"],
                "correct_answer": 3,
                "explanation": "Future Perfect Continuous describes duration up to a point in the future.",
                "xp_reward": 10,
                "skill": "grammar"
            },
            {
                "type": "reorder",
                "question": "Order the words: 'been / have / I / working / all day'",
                "correct_order": ["I", "have", "been", "working", "all day"],
                "xp_reward": 10,
                "skill": "grammar"
            },
            {
                "type": "multiple_choice",
                "question": "Which sentence is Present Perfect Continuous?",
                "options": [
                    "I worked yesterday.",
                    "I have been working all morning.",
                    "I will work tomorrow.",
                    "I am working now."
                ],
                "correct_answer": 1,
                "explanation": "'Have been working' is Present Perfect Continuous (have + been + verb-ing).",
                "xp_reward": 10,
                "skill": "grammar"
            },
            {
                "type": "fill_blank",
                "question": "Complete: 'They _____ for the test for weeks.' (Present Perfect Continuous)",
                "correct_answer": "have been preparing",
                "hint": "have + been + verb-ing",
                "xp_reward": 15,
                "skill": "grammar"
            },
            {
                "type": "translation",
                "question": "Translate: 'Tôi đã và đang học tiếng Anh được 2 năm'",
                "correct_answer": "I have been learning English for 2 years",
                "alternatives": ["I have been studying English for 2 years", "I've been learning English for 2 years"],
                "xp_reward": 15,
                "skill": "grammar"
            },
            {
                "type": "error_correction",
                "question": "Find and correct the error: 'She has been work here since 2020.'",
                "original": "She has been work here since 2020.",
                "correct_answer": "She has been working here since 2020.",
                "explanation": "After 'has been', use the -ing form of the verb.",
                "xp_reward": 15,
                "skill": "grammar"
            },
            {
                "type": "multiple_choice",
                "question": "When he arrived, I _____ for two hours.",
                "options": ["waited", "have been waiting", "had been waiting", "wait"],
                "correct_answer": 2,
                "explanation": "Past Perfect Continuous is used for an action that was happening before another past action.",
                "xp_reward": 10,
                "skill": "grammar"
            },
            {
                "type": "writing",
                "question": "Write 3 sentences using present perfect continuous about your daily routine.",
                "requirements": ["Use 'have been' or 'has been'", "Include time expressions (for/since)", "Use 3 different activities"],
                "example_answer": "I have been studying programming for 6 months. My friend has been working at the office since morning. We have been playing tennis for an hour.",
                "xp_reward": 25,
                "skill": "writing"
            }
        ]
    }
}


# ==========================================
# 3. VOCABULARY ITEMS DATA  
# ==========================================
VOCABULARY_ITEMS = [
    # Greetings
    {"word": "hello", "pronunciation": "/həˈləʊ/", "definition": "a greeting", "translation": {"vi": "xin chào"}, "part_of_speech": "interjection", "difficulty_level": "A1", "tags": ["greetings"]},
    {"word": "goodbye", "pronunciation": "/ɡʊdˈbaɪ/", "definition": "said when parting", "translation": {"vi": "tạm biệt"}, "part_of_speech": "interjection", "difficulty_level": "A1", "tags": ["greetings"]},
    {"word": "please", "pronunciation": "/pliːz/", "definition": "used to add politeness", "translation": {"vi": "làm ơn"}, "part_of_speech": "adverb", "difficulty_level": "A1", "tags": ["basics"]},
    {"word": "thank you", "pronunciation": "/θæŋk juː/", "definition": "expressing gratitude", "translation": {"vi": "cảm ơn"}, "part_of_speech": "phrase", "difficulty_level": "A1", "tags": ["basics"]},
    {"word": "sorry", "pronunciation": "/ˈsɒri/", "definition": "expressing regret", "translation": {"vi": "xin lỗi"}, "part_of_speech": "adjective", "difficulty_level": "A1", "tags": ["basics"]},
    
    # Numbers
    {"word": "one", "pronunciation": "/wʌn/", "definition": "the number 1", "translation": {"vi": "một"}, "part_of_speech": "noun", "difficulty_level": "A1", "tags": ["numbers"]},
    {"word": "two", "pronunciation": "/tuː/", "definition": "the number 2", "translation": {"vi": "hai"}, "part_of_speech": "noun", "difficulty_level": "A1", "tags": ["numbers"]},
    {"word": "three", "pronunciation": "/θriː/", "definition": "the number 3", "translation": {"vi": "ba"}, "part_of_speech": "noun", "difficulty_level": "A1", "tags": ["numbers"]},
    {"word": "ten", "pronunciation": "/ten/", "definition": "the number 10", "translation": {"vi": "mười"}, "part_of_speech": "noun", "difficulty_level": "A1", "tags": ["numbers"]},
    {"word": "hundred", "pronunciation": "/ˈhʌndrəd/", "definition": "the number 100", "translation": {"vi": "một trăm"}, "part_of_speech": "noun", "difficulty_level": "A1", "tags": ["numbers"]},
    
    # Colors
    {"word": "red", "pronunciation": "/red/", "definition": "color of blood", "translation": {"vi": "đỏ"}, "part_of_speech": "adjective", "difficulty_level": "A1", "tags": ["colors"]},
    {"word": "blue", "pronunciation": "/bluː/", "definition": "color of the sky", "translation": {"vi": "xanh dương"}, "part_of_speech": "adjective", "difficulty_level": "A1", "tags": ["colors"]},
    {"word": "green", "pronunciation": "/ɡriːn/", "definition": "color of grass", "translation": {"vi": "xanh lá"}, "part_of_speech": "adjective", "difficulty_level": "A1", "tags": ["colors"]},
    {"word": "yellow", "pronunciation": "/ˈjeləʊ/", "definition": "color of sun", "translation": {"vi": "vàng"}, "part_of_speech": "adjective", "difficulty_level": "A1", "tags": ["colors"]},
    {"word": "black", "pronunciation": "/blæk/", "definition": "darkest color", "translation": {"vi": "đen"}, "part_of_speech": "adjective", "difficulty_level": "A1", "tags": ["colors"]},
    {"word": "white", "pronunciation": "/waɪt/", "definition": "lightest color", "translation": {"vi": "trắng"}, "part_of_speech": "adjective", "difficulty_level": "A1", "tags": ["colors"]},
    
    # Family
    {"word": "mother", "pronunciation": "/ˈmʌðə/", "definition": "female parent", "translation": {"vi": "mẹ"}, "part_of_speech": "noun", "difficulty_level": "A1", "tags": ["family"]},
    {"word": "father", "pronunciation": "/ˈfɑːðə/", "definition": "male parent", "translation": {"vi": "bố"}, "part_of_speech": "noun", "difficulty_level": "A1", "tags": ["family"]},
    {"word": "sister", "pronunciation": "/ˈsɪstə/", "definition": "female sibling", "translation": {"vi": "chị/em gái"}, "part_of_speech": "noun", "difficulty_level": "A1", "tags": ["family"]},
    {"word": "brother", "pronunciation": "/ˈbrʌðə/", "definition": "male sibling", "translation": {"vi": "anh/em trai"}, "part_of_speech": "noun", "difficulty_level": "A1", "tags": ["family"]},
    
    # Food
    {"word": "water", "pronunciation": "/ˈwɔːtə/", "definition": "clear liquid for drinking", "translation": {"vi": "nước"}, "part_of_speech": "noun", "difficulty_level": "A1", "tags": ["food"]},
    {"word": "food", "pronunciation": "/fuːd/", "definition": "things to eat", "translation": {"vi": "thức ăn"}, "part_of_speech": "noun", "difficulty_level": "A1", "tags": ["food"]},
    {"word": "bread", "pronunciation": "/bred/", "definition": "baked flour food", "translation": {"vi": "bánh mì"}, "part_of_speech": "noun", "difficulty_level": "A1", "tags": ["food"]},
    {"word": "rice", "pronunciation": "/raɪs/", "definition": "grain food", "translation": {"vi": "cơm/gạo"}, "part_of_speech": "noun", "difficulty_level": "A1", "tags": ["food"]},
    {"word": "coffee", "pronunciation": "/ˈkɒfi/", "definition": "caffeinated drink", "translation": {"vi": "cà phê"}, "part_of_speech": "noun", "difficulty_level": "A1", "tags": ["food"]},
    
    # Business English (B1-B2)
    {"word": "meeting", "pronunciation": "/ˈmiːtɪŋ/", "definition": "formal gathering", "translation": {"vi": "cuộc họp"}, "part_of_speech": "noun", "difficulty_level": "B1", "tags": ["business"]},
    {"word": "deadline", "pronunciation": "/ˈdedlaɪn/", "definition": "final date for task", "translation": {"vi": "hạn chót"}, "part_of_speech": "noun", "difficulty_level": "B1", "tags": ["business"]},
    {"word": "negotiate", "pronunciation": "/nɪˈɡəʊʃieɪt/", "definition": "to discuss terms", "translation": {"vi": "đàm phán"}, "part_of_speech": "verb", "difficulty_level": "B2", "tags": ["business"]},
    {"word": "proposal", "pronunciation": "/prəˈpəʊzl/", "definition": "formal suggestion", "translation": {"vi": "đề xuất"}, "part_of_speech": "noun", "difficulty_level": "B1", "tags": ["business"]},
    {"word": "contract", "pronunciation": "/ˈkɒntrækt/", "definition": "legal agreement", "translation": {"vi": "hợp đồng"}, "part_of_speech": "noun", "difficulty_level": "B1", "tags": ["business"]},
    
    # Travel
    {"word": "airport", "pronunciation": "/ˈeəpɔːt/", "definition": "place for planes", "translation": {"vi": "sân bay"}, "part_of_speech": "noun", "difficulty_level": "A2", "tags": ["travel"]},
    {"word": "passport", "pronunciation": "/ˈpɑːspɔːt/", "definition": "travel document", "translation": {"vi": "hộ chiếu"}, "part_of_speech": "noun", "difficulty_level": "A2", "tags": ["travel"]},
    {"word": "hotel", "pronunciation": "/həʊˈtel/", "definition": "place to stay", "translation": {"vi": "khách sạn"}, "part_of_speech": "noun", "difficulty_level": "A1", "tags": ["travel"]},
    {"word": "luggage", "pronunciation": "/ˈlʌɡɪdʒ/", "definition": "travel bags", "translation": {"vi": "hành lý"}, "part_of_speech": "noun", "difficulty_level": "A2", "tags": ["travel"]},
    {"word": "reservation", "pronunciation": "/ˌrezəˈveɪʃn/", "definition": "booking", "translation": {"vi": "đặt chỗ"}, "part_of_speech": "noun", "difficulty_level": "A2", "tags": ["travel"]},
]


# ==========================================
# MAIN SEEDING FUNCTIONS
# ==========================================

async def seed_categories(db: AsyncSession):
    """Seed course categories."""
    print("\n[1/4] Seeding Course Categories...")
    
    created = 0
    for cat_data in COURSE_CATEGORIES:
        # Check if category exists
        result = await db.execute(
            select(CourseCategory).where(CourseCategory.slug == cat_data["slug"])
        )
        existing = result.scalar_one_or_none()
        
        if not existing:
            category = CourseCategory(**cat_data)
            db.add(category)
            created += 1
            print(f"  + Created: {cat_data['name']}")
        else:
            print(f"  - Exists: {cat_data['name']}")
    
    await db.commit()
    print(f"  Total categories created: {created}")


async def seed_lesson_content(db: AsyncSession):
    """Seed lesson content with exercises."""
    print("\n[2/4] Seeding Lesson Content...")
    
    updated = 0
    for lesson_title, content in LESSON_CONTENTS.items():
        # Find the lesson (use first() to handle duplicates)
        result = await db.execute(
            select(Lesson).where(Lesson.title == lesson_title).limit(1)
        )
        lesson = result.scalar_one_or_none()
        
        if lesson:
            # Update the lesson content
            lesson.content = content
            lesson.total_exercises = len(content.get("exercises", []))
            lesson.content_version = 2  # Mark as updated content
            updated += 1
            print(f"  + Updated: {lesson_title} ({lesson.total_exercises} exercises)")
        else:
            print(f"  ! Lesson not found: {lesson_title}")
    
    await db.commit()
    print(f"  Total lessons updated: {updated}")


async def seed_vocabulary(db: AsyncSession):
    """Seed vocabulary items."""
    print("\n[3/4] Seeding Vocabulary Items...")
    
    # Mapping for part of speech strings to enum
    pos_map = {
        "noun": PartOfSpeech.NOUN,
        "verb": PartOfSpeech.VERB,
        "adjective": PartOfSpeech.ADJECTIVE,
        "adverb": PartOfSpeech.ADVERB,
        "pronoun": PartOfSpeech.PRONOUN,
        "preposition": PartOfSpeech.PREPOSITION,
        "conjunction": PartOfSpeech.CONJUNCTION,
        "interjection": PartOfSpeech.INTERJECTION,
        "phrase": PartOfSpeech.PHRASE,
    }
    
    # Mapping for difficulty level strings to enum
    level_map = {
        "A1": DifficultyLevel.A1,
        "A2": DifficultyLevel.A2,
        "B1": DifficultyLevel.B1,
        "B2": DifficultyLevel.B2,
        "C1": DifficultyLevel.C1,
        "C2": DifficultyLevel.C2,
    }
    
    created = 0
    for vocab_data in VOCABULARY_ITEMS:
        # Check if vocabulary exists
        result = await db.execute(
            select(VocabularyItem).where(VocabularyItem.word == vocab_data["word"])
        )
        existing = result.scalar_one_or_none()
        
        if not existing:
            # Convert string values to enum values
            item_data = vocab_data.copy()
            item_data["part_of_speech"] = pos_map.get(vocab_data["part_of_speech"], PartOfSpeech.NOUN)
            item_data["difficulty_level"] = level_map.get(vocab_data["difficulty_level"], DifficultyLevel.A1)
            
            vocab = VocabularyItem(**item_data)
            db.add(vocab)
            created += 1
        
    await db.commit()
    print(f"  Total vocabulary items created: {created}")


async def update_course_categories(db: AsyncSession):
    """Link courses to appropriate categories."""
    print("\n[4/4] Linking Courses to Categories...")
    
    # Get categories
    result = await db.execute(select(CourseCategory))
    categories = {cat.slug: cat.id for cat in result.scalars().all()}
    
    if not categories:
        print("  ! No categories found, skipping...")
        return
    
    # Get courses
    result = await db.execute(select(Course))
    courses = result.scalars().all()
    
    updated = 0
    for course in courses:
        category_id = None
        title_lower = course.title.lower()
        tags = course.tags if isinstance(course.tags, list) else []
        
        # Determine category based on title/tags
        if "grammar" in title_lower or "grammar" in str(tags):
            category_id = categories.get("grammar")
        elif "business" in title_lower:
            category_id = categories.get("business")
        elif "travel" in title_lower:
            category_id = categories.get("travel")
        elif "ielts" in title_lower or "toefl" in title_lower or "test" in title_lower:
            category_id = categories.get("test-prep")
        elif "conversation" in title_lower:
            category_id = categories.get("conversation")
        else:
            category_id = categories.get("vocabulary")  # Default
        
        if category_id and course.category_id != category_id:
            course.category_id = category_id
            updated += 1
            print(f"  + Linked: {course.title}")
    
    await db.commit()
    
    # Update category course counts
    for slug, cat_id in categories.items():
        result = await db.execute(
            text("SELECT COUNT(*) FROM courses WHERE category_id = :cat_id"),
            {"cat_id": str(cat_id)}
        )
        count = result.scalar()
        await db.execute(
            text("UPDATE course_categories SET course_count = :count WHERE id = :cat_id"),
            {"count": count, "cat_id": str(cat_id)}
        )
    
    await db.commit()
    print(f"  Total courses linked: {updated}")


async def main():
    """Main seeding function."""
    print("=" * 60)
    print("LEXILINGO - COURSE CONTENT SEEDING")
    print("=" * 60)
    
    async with AsyncSessionLocal() as db:
        try:
            await seed_categories(db)
            await seed_lesson_content(db)
            await seed_vocabulary(db)
            await update_course_categories(db)
            
            print("\n" + "=" * 60)
            print("SEEDING COMPLETE!")
            print("=" * 60)
            
            # Show summary
            result = await db.execute(text("SELECT COUNT(*) FROM course_categories"))
            cat_count = result.scalar()
            
            result = await db.execute(text("SELECT COUNT(*) FROM lessons WHERE content IS NOT NULL"))
            lesson_count = result.scalar()
            
            result = await db.execute(text("SELECT COUNT(*) FROM vocabulary_items"))
            vocab_count = result.scalar()
            
            print(f"\nSummary:")
            print(f"  - Categories: {cat_count}")
            print(f"  - Lessons with content: {lesson_count}")
            print(f"  - Vocabulary items: {vocab_count}")
            
        except Exception as e:
            print(f"\nError during seeding: {e}")
            raise


if __name__ == "__main__":
    asyncio.run(main())
