"""
Seed Sample Stories for Topic-Based Conversation

Run this script to populate the MongoDB 'stories' collection with sample data.

Usage:
    cd ai-service
    python -m scripts.seed_stories
"""

import asyncio
import logging
from datetime import datetime
from motor.motor_asyncio import AsyncIOMotorClient

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Sample story data
SAMPLE_STORIES = [
    {
        "story_id": "story_airport_travel",
        "title": {
            "en": "Airport Travel Adventure",
            "vi": "Cuộc phiêu lưu tại sân bay"
        },
        "difficulty_level": "B1",
        "category": "travel",
        "estimated_minutes": 15,
        "cover_image_url": None,
        "context_description": {
            "setting": "International airport departure terminal",
            "scenario": "You are a traveler checking in for an international flight. You need to navigate the check-in counter, security checkpoint, and find your boarding gate. The AI plays airport staff roles.",
            "objectives": [
                "Practice airport vocabulary and common phrases",
                "Learn how to handle check-in conversations",
                "Understand security procedures in English",
                "Master polite request forms (Could I...?, Would you...?)"
            ]
        },
        "role_persona": {
            "name": "Sarah",
            "role": "Airline Check-In Agent",
            "personality": "Professional but warm, patient with non-native speakers, helpful and reassuring",
            "speaking_style": "Clear enunciation, uses simple sentences when needed, occasionally uses airport jargon with explanations",
            "background": "Works for SkyWings Airlines, has been helping international travelers for 5 years, genuinely enjoys meeting people from different cultures"
        },
        "vocabulary_list": [
            {
                "term": "boarding pass",
                "definition": "A document that allows you to board the airplane",
                "example_in_story": "Here is your boarding pass. Gate 23, boarding at 2:45 PM.",
                "part_of_speech": "noun",
                "phonetic": "/ˈbɔːrdɪŋ pæs/"
            },
            {
                "term": "check in",
                "definition": "To register at the airline counter before your flight",
                "example_in_story": "Would you like to check in your luggage?",
                "part_of_speech": "phrasal verb",
                "phonetic": "/tʃek ɪn/"
            },
            {
                "term": "carry-on luggage",
                "definition": "A small bag you can take with you on the plane",
                "example_in_story": "Is this your only carry-on luggage?",
                "part_of_speech": "noun",
                "phonetic": "/ˈkæri ɒn ˈlʌɡɪdʒ/"
            },
            {
                "term": "departure gate",
                "definition": "The area where you wait to board your plane",
                "example_in_story": "Your departure gate is C12, down the hall to your left.",
                "part_of_speech": "noun",
                "phonetic": "/dɪˈpɑːtʃə ɡeɪt/"
            },
            {
                "term": "flight delay",
                "definition": "When a plane leaves later than scheduled",
                "example_in_story": "I'm sorry, there's a slight flight delay of 30 minutes.",
                "part_of_speech": "noun",
                "phonetic": "/flaɪt dɪˈleɪ/"
            }
        ],
        "grammar_points": [
            {
                "grammar_structure": "Would you like to...?",
                "explanation": "Polite way to offer something or make suggestions",
                "usage_in_story": "Service professionals use this to offer options politely",
                "examples": [
                    "Would you like to choose a window seat?",
                    "Would you like me to print your boarding pass?"
                ]
            },
            {
                "grammar_structure": "Could I see...?",
                "explanation": "Polite request for something",
                "usage_in_story": "Staff asking to see documents",
                "examples": [
                    "Could I see your passport, please?",
                    "Could I see your booking confirmation?"
                ]
            },
            {
                "grammar_structure": "I'd like to...",
                "explanation": "Polite way to express what you want",
                "usage_in_story": "Travelers making requests",
                "examples": [
                    "I'd like to check in for my flight.",
                    "I'd like an aisle seat, please."
                ]
            }
        ],
        "conversation_flow": {
            "opening_prompt": "Good afternoon! Welcome to SkyWings Airlines. Are you here to check in for your flight today?",
            "key_milestones": [
                "Greeting and flight confirmation",
                "Passport and ticket verification",
                "Luggage check-in discussion",
                "Seat selection",
                "Gate and boarding information"
            ],
            "closing_scenarios": [
                "Successfully checked in and heading to gate",
                "Resolving an issue (overweight luggage, seat change)"
            ]
        },
        "is_published": True,
        "tags": ["travel", "airport", "check-in", "conversation", "beginner-friendly"],
        "created_at": datetime.utcnow(),
        "updated_at": datetime.utcnow()
    },
    {
        "story_id": "story_job_interview",
        "title": {
            "en": "Job Interview Success",
            "vi": "Phỏng vấn xin việc thành công"
        },
        "difficulty_level": "B2",
        "category": "business",
        "estimated_minutes": 20,
        "cover_image_url": None,
        "context_description": {
            "setting": "Modern office building, interview room",
            "scenario": "You are applying for a marketing position at a tech company. The AI plays the role of the HR manager conducting the interview. Practice answering common interview questions professionally.",
            "objectives": [
                "Practice professional vocabulary for job interviews",
                "Learn to talk about your experience and skills",
                "Master answering behavioral interview questions",
                "Practice using past tense to describe achievements"
            ]
        },
        "role_persona": {
            "name": "Michael Chen",
            "role": "HR Manager",
            "personality": "Professional, friendly but evaluative, genuinely interested in candidates, fair and encouraging",
            "speaking_style": "Clear business English, asks follow-up questions, gives positive feedback when appropriate",
            "background": "HR Manager at TechVision Inc., has conducted over 500 interviews, values authenticity and growth mindset in candidates"
        },
        "vocabulary_list": [
            {
                "term": "qualifications",
                "definition": "Skills, experience, or education that make you suitable for a job",
                "example_in_story": "Can you tell me about your qualifications for this role?",
                "part_of_speech": "noun",
                "phonetic": "/ˌkwɒlɪfɪˈkeɪʃənz/"
            },
            {
                "term": "team player",
                "definition": "Someone who works well with others in a group",
                "example_in_story": "We're looking for a team player who can collaborate effectively.",
                "part_of_speech": "noun",
                "phonetic": "/tiːm ˈpleɪər/"
            },
            {
                "term": "strengths and weaknesses",
                "definition": "Things you are good at and areas for improvement",
                "example_in_story": "What would you say are your main strengths and weaknesses?",
                "part_of_speech": "noun phrase",
                "phonetic": "/streŋθs ənd ˈwiːknəsɪz/"
            },
            {
                "term": "career goals",
                "definition": "What you want to achieve professionally in the future",
                "example_in_story": "Where do you see yourself in 5 years? What are your career goals?",
                "part_of_speech": "noun phrase",
                "phonetic": "/kəˈrɪər ɡəʊlz/"
            }
        ],
        "grammar_points": [
            {
                "grammar_structure": "I have been + verb-ing (Present Perfect Continuous)",
                "explanation": "Describe ongoing experience up to now",
                "usage_in_story": "Talking about work experience",
                "examples": [
                    "I have been working in marketing for 3 years.",
                    "I have been developing my leadership skills."
                ]
            },
            {
                "grammar_structure": "I managed to + verb",
                "explanation": "Describe successful achievements despite difficulty",
                "usage_in_story": "Highlighting accomplishments",
                "examples": [
                    "I managed to increase sales by 20%.",
                    "I managed to complete the project ahead of schedule."
                ]
            }
        ],
        "conversation_flow": {
            "opening_prompt": "Good morning! Please, have a seat. Thank you for coming in today. My name is Michael Chen, and I'm the HR Manager here at TechVision. How are you doing today?",
            "key_milestones": [
                "Introduction and ice-breaker",
                "Tell me about yourself",
                "Work experience discussion",
                "Strengths and weaknesses",
                "Why this company?",
                "Questions from candidate"
            ],
            "closing_scenarios": [
                "Positive interview conclusion with next steps",
                "Handling a challenging question gracefully"
            ]
        },
        "is_published": True,
        "tags": ["business", "interview", "professional", "career", "intermediate"],
        "created_at": datetime.utcnow(),
        "updated_at": datetime.utcnow()
    },
    {
        "story_id": "story_restaurant_order",
        "title": {
            "en": "Dining Out Experience",
            "vi": "Trải nghiệm ăn nhà hàng"
        },
        "difficulty_level": "A2",
        "category": "daily_life",
        "estimated_minutes": 10,
        "cover_image_url": None,
        "context_description": {
            "setting": "Cozy Italian restaurant",
            "scenario": "You are dining at an Italian restaurant. The AI plays the role of a friendly waiter. Practice ordering food, asking about the menu, and handling common dining situations.",
            "objectives": [
                "Learn restaurant vocabulary",
                "Practice ordering food politely",
                "Ask about ingredients and recommendations",
                "Handle the bill and tipping conversation"
            ]
        },
        "role_persona": {
            "name": "Marco",
            "role": "Restaurant Waiter",
            "personality": "Friendly, enthusiastic about food, patient with questions, makes recommendations warmly",
            "speaking_style": "Welcoming, uses food-related vocabulary, occasionally uses Italian food terms with English explanations",
            "background": "Has worked at Bella Italia for 3 years, passionate about authentic Italian cuisine, loves helping guests discover new dishes"
        },
        "vocabulary_list": [
            {
                "term": "appetizer",
                "definition": "A small dish served before the main course",
                "example_in_story": "Would you like to start with an appetizer?",
                "part_of_speech": "noun",
                "phonetic": "/ˈæpɪtaɪzər/"
            },
            {
                "term": "main course",
                "definition": "The largest or most important dish of a meal",
                "example_in_story": "For your main course, I recommend our signature pasta.",
                "part_of_speech": "noun",
                "phonetic": "/meɪn kɔːrs/"
            },
            {
                "term": "side dish",
                "definition": "A smaller dish served alongside the main course",
                "example_in_story": "This comes with your choice of side dish.",
                "part_of_speech": "noun",
                "phonetic": "/saɪd dɪʃ/"
            }
        ],
        "grammar_points": [
            {
                "grammar_structure": "Can I have...? / Could I get...?",
                "explanation": "Polite ways to order something",
                "usage_in_story": "Ordering food and drinks",
                "examples": [
                    "Can I have the pasta, please?",
                    "Could I get a glass of water?"
                ]
            },
            {
                "grammar_structure": "What do you recommend?",
                "explanation": "Asking for suggestions",
                "usage_in_story": "Asking waiter for recommendations",
                "examples": [
                    "What do you recommend for someone who likes seafood?",
                    "What's your most popular dish?"
                ]
            }
        ],
        "conversation_flow": {
            "opening_prompt": "Buonasera! Welcome to Bella Italia! My name is Marco, and I'll be your server today. Can I start you off with something to drink?",
            "key_milestones": [
                "Drinks order",
                "Menu questions and recommendations",
                "Food order",
                "Check on the meal",
                "Dessert offer",
                "Bill and payment"
            ],
            "closing_scenarios": [
                "Satisfied customer leaving with thanks",
                "Asking about a dish modification (allergy, preference)"
            ]
        },
        "is_published": True,
        "tags": ["restaurant", "food", "ordering", "daily", "beginner"],
        "created_at": datetime.utcnow(),
        "updated_at": datetime.utcnow()
    }
]


async def seed_stories():
    """Seed sample stories into MongoDB."""
    import os
    from dotenv import load_dotenv
    
    load_dotenv()
    
    mongo_uri = os.getenv("MONGODB_URI", "mongodb://localhost:27017")
    db_name = os.getenv("MONGODB_DB_NAME", "lexilingo")
    
    logger.info(f"Connecting to MongoDB at {mongo_uri}...")
    
    client = AsyncIOMotorClient(mongo_uri)
    db = client[db_name]
    collection = db["stories"]
    
    # Create indexes
    logger.info("Creating indexes...")
    await collection.create_index("story_id", unique=True)
    await collection.create_index([("difficulty_level", 1), ("is_published", 1)])
    await collection.create_index([("category", 1), ("is_published", 1)])
    await collection.create_index("tags")
    logger.info("✓ Indexes created")
    
    # Insert stories (upsert to avoid duplicates)
    for story in SAMPLE_STORIES:
        result = await collection.update_one(
            {"story_id": story["story_id"]},
            {"$set": story},
            upsert=True
        )
        if result.upserted_id:
            logger.info(f"✓ Inserted: {story['title']['en']}")
        else:
            logger.info(f"✓ Updated: {story['title']['en']}")
    
    # Verify
    count = await collection.count_documents({"is_published": True})
    logger.info(f"\n✅ Total published stories: {count}")
    
    client.close()
    logger.info("Done!")


if __name__ == "__main__":
    asyncio.run(seed_stories())
