"""
Games API Routes — English Learning Games
Phase 3: English Games + XP System

6 interactive games:
1. Word Scramble        GET /api/games/word-scramble
2. Matching             GET /api/games/matching
3. Spelling Bee         GET /api/games/spelling-bee
4. Hangman              GET /api/games/hangman
5. Fill in the Blank    GET /api/games/fill-blank
6. Grammar Quiz         GET /api/games/grammar-quiz

All endpoints return game-ready data (words shuffled, options randomized, etc).
Seed data is auto-loaded from GAME_WORDS_SEED on first request if DB is empty.
"""

import asyncio
import logging
import random
import uuid
from typing import Optional, List

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.user import User
from app.models.games import GameWord

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/games", tags=["Games"])

# ── CEFR Timer / XP Config ────────────────────────────────────────────────────

TIMER_BY_LEVEL = {
    "A1": 90, "A2": 90,
    "B1": 60, "B2": 60,
    "C1": 45, "C2": 45,
}

XP_BY_LEVEL = {
    "A1": 10, "A2": 10,
    "B1": 15, "B2": 20,
    "C1": 25, "C2": 30,
}

VALID_CEFR_LEVELS = {"A1", "A2", "B1", "B2", "C1", "C2"}

# ── Embedded Seed Words ───────────────────────────────────────────────────────
# Used to auto-seed DB if empty. Covers A1-C1 levels, multiple categories.

GAME_WORDS_SEED = [
    # ── A1 ───────────────────────────────────────────────────────────────────
    {"word": "cat",    "definition": "A small furry animal kept as a pet",            "hint": "Common house pet",                    "cefr_level": "A1", "category": "animals",    "letter_count": 3,  "xp_value": 5,  "ipa_pronunciation": "/kæt/",              "example_sentence": "The cat sat on the mat.",                "synonyms": ["kitten"],              "vietnamese_translation": "con mèo"},
    {"word": "dog",    "definition": "A domestic animal often kept as a pet",          "hint": "Man's best friend",                   "cefr_level": "A1", "category": "animals",    "letter_count": 3,  "xp_value": 5,  "ipa_pronunciation": "/dɒɡ/",              "example_sentence": "My dog likes to play fetch.",            "synonyms": ["puppy"],               "vietnamese_translation": "con chó"},
    {"word": "book",   "definition": "A set of printed pages bound together",          "hint": "You read it",                         "cefr_level": "A1", "category": "objects",    "letter_count": 4,  "xp_value": 5,  "ipa_pronunciation": "/bʊk/",              "example_sentence": "I read a book every night.",             "synonyms": ["volume"],              "vietnamese_translation": "quyển sách"},
    {"word": "house",  "definition": "A building where people live",                   "hint": "A place where you live",              "cefr_level": "A1", "category": "home",       "letter_count": 5,  "xp_value": 8,  "ipa_pronunciation": "/haʊs/",             "example_sentence": "We live in a big house.",                "synonyms": ["home", "dwelling"],    "vietnamese_translation": "ngôi nhà"},
    {"word": "apple",  "definition": "A round fruit with red or green skin",           "hint": "A common fruit",                      "cefr_level": "A1", "category": "food",       "letter_count": 5,  "xp_value": 8,  "ipa_pronunciation": "/ˈæpl/",             "example_sentence": "She eats an apple every day.",           "synonyms": [],                      "vietnamese_translation": "quả táo"},
    {"word": "water",  "definition": "A clear liquid that we drink",                   "hint": "You drink this every day",            "cefr_level": "A1", "category": "food",       "letter_count": 5,  "xp_value": 8,  "ipa_pronunciation": "/ˈwɔːtər/",          "example_sentence": "Drink eight glasses of water a day.",    "synonyms": ["liquid"],              "vietnamese_translation": "nước"},
    {"word": "school", "definition": "A place where children go to learn",             "hint": "Where students study",               "cefr_level": "A1", "category": "education",  "letter_count": 6,  "xp_value": 8,  "ipa_pronunciation": "/skuːl/",             "example_sentence": "The school opens at eight o'clock.",     "synonyms": ["academy"],             "vietnamese_translation": "trường học"},
    {"word": "happy",  "definition": "Feeling or showing pleasure",                    "hint": "Opposite of sad",                     "cefr_level": "A1", "category": "emotions",   "letter_count": 5,  "xp_value": 8,  "ipa_pronunciation": "/ˈhæpi/",            "example_sentence": "I am happy to meet you.",                "synonyms": ["glad", "joyful"],      "vietnamese_translation": "vui vẻ"},
    {"word": "chair",  "definition": "A piece of furniture to sit on",                 "hint": "You sit on this",                     "cefr_level": "A1", "category": "home",       "letter_count": 5,  "xp_value": 8,  "ipa_pronunciation": "/tʃeər/",            "example_sentence": "Please take a chair and sit down.",      "synonyms": ["seat"],                "vietnamese_translation": "cái ghế"},
    {"word": "bread",  "definition": "A food made from flour and baked",               "hint": "A staple food",                       "cefr_level": "A1", "category": "food",       "letter_count": 5,  "xp_value": 8,  "ipa_pronunciation": "/bred/",              "example_sentence": "I had bread and butter for breakfast.",  "synonyms": [],                      "vietnamese_translation": "bánh mì"},
    {"word": "table",  "definition": "A piece of furniture with a flat top and legs",  "hint": "You eat meals at this",               "cefr_level": "A1", "category": "home",       "letter_count": 5,  "xp_value": 8,  "ipa_pronunciation": "/ˈteɪbl/",           "example_sentence": "Put the books on the table.",            "synonyms": ["desk"],                "vietnamese_translation": "cái bàn"},
    {"word": "car",    "definition": "A motor vehicle with four wheels",               "hint": "A common means of transport",         "cefr_level": "A1", "category": "transport",  "letter_count": 3,  "xp_value": 5,  "ipa_pronunciation": "/kɑːr/",             "example_sentence": "He drives his car to work.",             "synonyms": ["automobile"],          "vietnamese_translation": "xe ô tô"},
    # ── A2 ───────────────────────────────────────────────────────────────────
    {"word": "travel",   "definition": "To go from one place to another",               "hint": "What tourists do",                    "cefr_level": "A2", "category": "travel",     "letter_count": 6,  "xp_value": 10, "ipa_pronunciation": "/ˈtrævl/",           "example_sentence": "She loves to travel around Asia.",       "synonyms": ["journey", "trip"],     "vietnamese_translation": "du lịch"},
    {"word": "garden",   "definition": "An area of land for growing plants",            "hint": "You grow flowers here",               "cefr_level": "A2", "category": "home",       "letter_count": 6,  "xp_value": 10, "ipa_pronunciation": "/ˈɡɑːdn/",          "example_sentence": "My grandmother has a beautiful garden.", "synonyms": ["yard"],                "vietnamese_translation": "khu vườn"},
    {"word": "family",   "definition": "A group of related people living together",     "hint": "Parents and children",               "cefr_level": "A2", "category": "people",     "letter_count": 6,  "xp_value": 10, "ipa_pronunciation": "/ˈfæmɪli/",         "example_sentence": "My family gathers every Sunday.",        "synonyms": ["relatives"],           "vietnamese_translation": "gia đình"},
    {"word": "kitchen",  "definition": "A room where food is prepared",                 "hint": "You cook here",                       "cefr_level": "A2", "category": "home",       "letter_count": 7,  "xp_value": 10, "ipa_pronunciation": "/ˈkɪtʃɪn/",         "example_sentence": "She is cooking in the kitchen.",         "synonyms": [],                      "vietnamese_translation": "nhà bếp"},
    {"word": "museum",   "definition": "A building displaying objects of history or art","hint": "A cultural place to visit",           "cefr_level": "A2", "category": "travel",     "letter_count": 6,  "xp_value": 10, "ipa_pronunciation": "/mjuːˈziːəm/",       "example_sentence": "We visited the natural history museum.", "synonyms": ["gallery"],             "vietnamese_translation": "bảo tàng"},
    {"word": "weather",  "definition": "The climate conditions at a given time",        "hint": "Rain, sun, or snow",                  "cefr_level": "A2", "category": "nature",     "letter_count": 7,  "xp_value": 10, "ipa_pronunciation": "/ˈweðər/",           "example_sentence": "The weather today is very cold.",        "synonyms": ["climate"],             "vietnamese_translation": "thời tiết"},
    {"word": "healthy",  "definition": "In good physical condition",                    "hint": "The opposite of sick",                "cefr_level": "A2", "category": "health",     "letter_count": 7,  "xp_value": 10, "ipa_pronunciation": "/ˈhelθi/",           "example_sentence": "Eating vegetables keeps you healthy.",   "synonyms": ["fit", "well"],         "vietnamese_translation": "khỏe mạnh"},
    {"word": "library",  "definition": "A building where books are kept for public use","hint": "Borrow books here",                    "cefr_level": "A2", "category": "education",  "letter_count": 7,  "xp_value": 10, "ipa_pronunciation": "/ˈlaɪbrəri/",        "example_sentence": "She goes to the library every week.",    "synonyms": [],                      "vietnamese_translation": "thư viện"},
    # ── B1 ───────────────────────────────────────────────────────────────────
    {"word": "adventure",    "definition": "An exciting experience or undertaking",          "hint": "Something exciting",               "cefr_level": "B1", "category": "travel",     "letter_count": 9,  "xp_value": 15, "ipa_pronunciation": "/ədˈventʃər/",       "example_sentence": "Life is a great adventure.",             "synonyms": ["expedition"],                    "vietnamese_translation": "cuộc phiêu lưu"},
    {"word": "knowledge",    "definition": "Information and skills acquired through experience","hint": "What you gain by learning",     "cefr_level": "B1", "category": "education",  "letter_count": 9,  "xp_value": 15, "ipa_pronunciation": "/ˈnɒlɪdʒ/",         "example_sentence": "Knowledge is power.",                    "synonyms": ["wisdom", "understanding"],       "vietnamese_translation": "kiến thức"},
    {"word": "necessary",    "definition": "Needed or required",                              "hint": "Cannot be done without",           "cefr_level": "B1", "category": "adjectives", "letter_count": 9,  "xp_value": 15, "ipa_pronunciation": "/ˈnesəseri/",        "example_sentence": "It is necessary to wear a helmet.",      "synonyms": ["essential", "required"],         "vietnamese_translation": "cần thiết"},
    {"word": "environment",  "definition": "The natural world around us",                    "hint": "Nature and surroundings",          "cefr_level": "B1", "category": "nature",     "letter_count": 11, "xp_value": 18, "ipa_pronunciation": "/ɪnˈvaɪrənmənt/",    "example_sentence": "We must protect the environment.",       "synonyms": ["surroundings", "nature"],        "vietnamese_translation": "môi trường"},
    {"word": "government",   "definition": "The group of people who control a country",      "hint": "Rules a country",                  "cefr_level": "B1", "category": "society",    "letter_count": 10, "xp_value": 18, "ipa_pronunciation": "/ˈɡʌvərnmənt/",      "example_sentence": "The government raised taxes.",           "synonyms": ["administration", "authority"],   "vietnamese_translation": "chính phủ"},
    {"word": "education",    "definition": "The process of teaching and learning",           "hint": "What schools provide",             "cefr_level": "B1", "category": "education",  "letter_count": 9,  "xp_value": 15, "ipa_pronunciation": "/ˌedʒʊˈkeɪʃn/",      "example_sentence": "Education is the key to success.",       "synonyms": ["schooling", "training"],         "vietnamese_translation": "giáo dục"},
    {"word": "beautiful",    "definition": "Pleasing the senses or mind aesthetically",      "hint": "Very attractive",                  "cefr_level": "B1", "category": "adjectives", "letter_count": 9,  "xp_value": 15, "ipa_pronunciation": "/ˈbjuːtɪfl/",        "example_sentence": "What a beautiful sunset!",               "synonyms": ["gorgeous", "lovely"],            "vietnamese_translation": "đẹp"},
    {"word": "successful",   "definition": "Achieving a desired goal or result",             "hint": "Having achieved your goals",       "cefr_level": "B1", "category": "adjectives", "letter_count": 10, "xp_value": 18, "ipa_pronunciation": "/səkˈsesfʊl/",       "example_sentence": "She became a successful author.",        "synonyms": ["accomplished", "prosperous"],    "vietnamese_translation": "thành công"},
    # ── B2 ───────────────────────────────────────────────────────────────────
    {"word": "enormous",      "definition": "Extremely large in size or amount",             "hint": "Very big",                         "cefr_level": "B2", "category": "adjectives", "letter_count": 8,  "xp_value": 20, "ipa_pronunciation": "/ɪˈnɔːməs/",        "example_sentence": "An enormous crowd gathered outside.",    "synonyms": ["huge", "gigantic", "vast"],       "vietnamese_translation": "khổng lồ"},
    {"word": "purchase",      "definition": "To buy something",                              "hint": "To acquire by paying",             "cefr_level": "B2", "category": "business",   "letter_count": 8,  "xp_value": 20, "ipa_pronunciation": "/ˈpɜːtʃəs/",        "example_sentence": "I need to purchase a new laptop.",       "synonyms": ["buy", "acquire"],                "vietnamese_translation": "mua"},
    {"word": "ancient",       "definition": "Very old, belonging to the distant past",       "hint": "From long ago",                    "cefr_level": "B2", "category": "history",    "letter_count": 7,  "xp_value": 20, "ipa_pronunciation": "/ˈeɪnʃənt/",        "example_sentence": "They explored the ancient ruins.",       "synonyms": ["old", "archaic"],                "vietnamese_translation": "cổ đại"},
    {"word": "journey",       "definition": "An act of traveling from one place to another", "hint": "A long trip",                      "cefr_level": "B2", "category": "travel",     "letter_count": 7,  "xp_value": 20, "ipa_pronunciation": "/ˈdʒɜːni/",         "example_sentence": "The journey took over ten hours.",       "synonyms": ["trip", "voyage"],                "vietnamese_translation": "hành trình"},
    {"word": "accomplish",    "definition": "To achieve or complete something successfully", "hint": "To reach a goal",                  "cefr_level": "B2", "category": "verbs",      "letter_count": 10, "xp_value": 20, "ipa_pronunciation": "/əˈkɒmplɪʃ/",       "example_sentence": "She accomplished her dream.",            "synonyms": ["achieve", "fulfill"],            "vietnamese_translation": "hoàn thành"},
    {"word": "accommodation", "definition": "A place to stay such as a room or house",      "hint": "Where you stay when travelling",   "cefr_level": "B2", "category": "travel",     "letter_count": 13, "xp_value": 25, "ipa_pronunciation": "/əˌkɒməˈdeɪʃn/",    "example_sentence": "The hotel accommodation was excellent.", "synonyms": ["lodging", "housing"],            "vietnamese_translation": "chỗ ở"},
    # ── C1 ───────────────────────────────────────────────────────────────────
    {"word": "sophisticated", "definition": "Having refined knowledge or tastes",            "hint": "Cultured and worldly",             "cefr_level": "C1", "category": "adjectives", "letter_count": 13, "xp_value": 30, "ipa_pronunciation": "/səˈfɪstɪkeɪtɪd/",  "example_sentence": "Her taste in art is very sophisticated.","synonyms": ["refined", "worldly"],            "vietnamese_translation": "tinh tế"},
    {"word": "unprecedented", "definition": "Never done or known before",                    "hint": "Totally new and unique",           "cefr_level": "C1", "category": "adjectives", "letter_count": 13, "xp_value": 30, "ipa_pronunciation": "/ʌnˈpresɪdentɪd/",  "example_sentence": "The storm caused unprecedented damage.", "synonyms": ["unheard-of", "novel"],           "vietnamese_translation": "chưa từng có"},
    {"word": "conscientious", "definition": "Wishing to do one's work or duty well",        "hint": "Careful and thorough",             "cefr_level": "C1", "category": "adjectives", "letter_count": 13, "xp_value": 30, "ipa_pronunciation": "/ˌkɒnʃiˈenʃəs/",    "example_sentence": "She is a conscientious worker.",         "synonyms": ["diligent", "thorough"],          "vietnamese_translation": "tận tâm"},
    {"word": "ambiguous",     "definition": "Open to more than one interpretation",         "hint": "Can mean more than one thing",     "cefr_level": "C1", "category": "adjectives", "letter_count": 9,  "xp_value": 25, "ipa_pronunciation": "/æmˈbɪɡjuəs/",      "example_sentence": "The contract clause was ambiguous.",     "synonyms": ["unclear", "vague"],              "vietnamese_translation": "mơ hồ"},
]

# ── Hangman Fallback Words ─────────────────────────────────────────────────────
# Used when the game_words table is completely empty.

HANGMAN_FALLBACK_WORDS = [
    {"word": "cat",     "category": "animals",   "hint": "Common house pet",            "definition": "A small furry animal kept as a pet",             "letter_count": 3,  "xp_value": 5,  "cefr_level": "A1"},
    {"word": "book",    "category": "objects",   "hint": "You read it",                 "definition": "A set of printed pages bound together",           "letter_count": 4,  "xp_value": 5,  "cefr_level": "A1"},
    {"word": "apple",   "category": "food",      "hint": "A red or green fruit",        "definition": "A round fruit with red or green skin",            "letter_count": 5,  "xp_value": 8,  "cefr_level": "A1"},
    {"word": "school",  "category": "education", "hint": "Where students go to learn",  "definition": "A place where children go to learn",              "letter_count": 6,  "xp_value": 8,  "cefr_level": "A1"},
    {"word": "garden",  "category": "home",      "hint": "Outdoor area with plants",    "definition": "An area of land for growing plants",              "letter_count": 6,  "xp_value": 10, "cefr_level": "A2"},
    {"word": "travel",  "category": "travel",    "hint": "What tourists do",            "definition": "To go from one place to another",                 "letter_count": 6,  "xp_value": 10, "cefr_level": "A2"},
    {"word": "museum",  "category": "travel",    "hint": "Cultural place to visit",     "definition": "A building displaying objects of history or art", "letter_count": 6,  "xp_value": 10, "cefr_level": "A2"},
    {"word": "journey", "category": "travel",    "hint": "A long trip",                 "definition": "An act of traveling from one place to another",   "letter_count": 7,  "xp_value": 20, "cefr_level": "B2"},
]

# ── Fill in the Blank Question Bank ───────────────────────────────────────────
# Completely separate from the grammar quiz bank.
# Topics per level:
#   A1 → present simple, to be, possessives
#   A2 → past simple, going to
#   B1 → present perfect, modals
#   B2 → passive, conditionals
#
# Each entry: sentence (with '___'), options (4), correct_answer (str),
#             grammar_tip, cefr_level

FILL_BLANK_BANK: dict = {
    "A1": [
        {
            "sentence": "She ___ a teacher.",
            "options": ["is", "are", "am", "be"],
            "correct_answer": "is",
            "grammar_tip": "To be: I am / You are / He/She/It is.",
            "cefr_level": "A1",
        },
        {
            "sentence": "I ___ from Vietnam.",
            "options": ["am", "is", "are", "be"],
            "correct_answer": "am",
            "grammar_tip": "To be: always use 'am' with 'I'.",
            "cefr_level": "A1",
        },
        {
            "sentence": "They ___ students.",
            "options": ["are", "is", "am", "be"],
            "correct_answer": "are",
            "grammar_tip": "To be: They/We/You are (plural subjects).",
            "cefr_level": "A1",
        },
        {
            "sentence": "He ___ to school every day.",
            "options": ["goes", "go", "going", "gone"],
            "correct_answer": "goes",
            "grammar_tip": "Present Simple: He/She/It + verb + -s/-es.",
            "cefr_level": "A1",
        },
        {
            "sentence": "We ___ tennis on weekends.",
            "options": ["play", "plays", "playing", "played"],
            "correct_answer": "play",
            "grammar_tip": "Present Simple: I/You/We/They + base verb (no -s).",
            "cefr_level": "A1",
        },
        {
            "sentence": "___ you like coffee?",
            "options": ["Do", "Does", "Did", "Are"],
            "correct_answer": "Do",
            "grammar_tip": "Yes/No questions: Do + I/you/we/they + base verb?",
            "cefr_level": "A1",
        },
        {
            "sentence": "This is ___ book.",
            "options": ["my", "me", "I", "mine"],
            "correct_answer": "my",
            "grammar_tip": "Possessive adjectives: my, your, his, her, its, our, their.",
            "cefr_level": "A1",
        },
        {
            "sentence": "That bag is ___.",
            "options": ["hers", "her", "she", "herself"],
            "correct_answer": "hers",
            "grammar_tip": "Possessive pronouns: mine, yours, his, hers, ours, theirs.",
            "cefr_level": "A1",
        },
        {
            "sentence": "I have ___ apple.",
            "options": ["an", "a", "the", "—"],
            "correct_answer": "an",
            "grammar_tip": "Use 'an' before vowel sounds (a, e, i, o, u).",
            "cefr_level": "A1",
        },
        {
            "sentence": "She doesn't ___ football.",
            "options": ["like", "likes", "liked", "liking"],
            "correct_answer": "like",
            "grammar_tip": "After doesn't/don't, always use the base form of the verb.",
            "cefr_level": "A1",
        },
        {
            "sentence": "There ___ a cat on the chair.",
            "options": ["is", "are", "am", "be"],
            "correct_answer": "is",
            "grammar_tip": "There is (singular noun) / There are (plural noun).",
            "cefr_level": "A1",
        },
        {
            "sentence": "___ coat is this?",
            "options": ["Whose", "Who", "Which", "What"],
            "correct_answer": "Whose",
            "grammar_tip": "'Whose' asks about ownership of something.",
            "cefr_level": "A1",
        },
        {
            "sentence": "The cat drinks ___ milk.",
            "options": ["its", "it", "their", "his"],
            "correct_answer": "its",
            "grammar_tip": "Use 'its' (no apostrophe) for an animal or thing.",
            "cefr_level": "A1",
        },
        {
            "sentence": "He ___ a doctor.",
            "options": ["is", "are", "am", "be"],
            "correct_answer": "is",
            "grammar_tip": "To be: He/She/It is (3rd person singular).",
            "cefr_level": "A1",
        },
    ],
    "A2": [
        {
            "sentence": "She ___ her homework yesterday.",
            "options": ["did", "do", "does", "done"],
            "correct_answer": "did",
            "grammar_tip": "Past Simple: use 'did' as auxiliary in questions/negatives.",
            "cefr_level": "A2",
        },
        {
            "sentence": "I ___ to Paris last year.",
            "options": ["went", "go", "gone", "going"],
            "correct_answer": "went",
            "grammar_tip": "Past Simple of 'go' is the irregular form 'went'.",
            "cefr_level": "A2",
        },
        {
            "sentence": "He ___ TV all evening.",
            "options": ["watched", "watch", "watching", "watches"],
            "correct_answer": "watched",
            "grammar_tip": "Past Simple regular verbs: base verb + -ed.",
            "cefr_level": "A2",
        },
        {
            "sentence": "We ___ not eat out last night.",
            "options": ["did", "do", "does", "were"],
            "correct_answer": "did",
            "grammar_tip": "Negative Past Simple: did not (didn't) + base verb.",
            "cefr_level": "A2",
        },
        {
            "sentence": "She ___ going to visit her parents next Sunday.",
            "options": ["is", "are", "am", "be"],
            "correct_answer": "is",
            "grammar_tip": "Be going to: am/is/are + going to + base verb (future plan).",
            "cefr_level": "A2",
        },
        {
            "sentence": "They ___ going to study tonight.",
            "options": ["are", "is", "am", "be"],
            "correct_answer": "are",
            "grammar_tip": "Be going to with plural subject: They/We/You are going to.",
            "cefr_level": "A2",
        },
        {
            "sentence": "I ___ going to cook dinner later.",
            "options": ["am", "is", "are", "be"],
            "correct_answer": "am",
            "grammar_tip": "Be going to: I am going to.",
            "cefr_level": "A2",
        },
        {
            "sentence": "___ you at school yesterday?",
            "options": ["Were", "Was", "Are", "Did"],
            "correct_answer": "Were",
            "grammar_tip": "Past of 'to be': I/He/She/It was; You/We/They were.",
            "cefr_level": "A2",
        },
        {
            "sentence": "The film ___ very long.",
            "options": ["was", "were", "is", "are"],
            "correct_answer": "was",
            "grammar_tip": "Past of 'to be' for singular: was.",
            "cefr_level": "A2",
        },
        {
            "sentence": "She is the ___ student in class.",
            "options": ["best", "better", "good", "most good"],
            "correct_answer": "best",
            "grammar_tip": "Superlative of 'good' is 'best' (irregular form).",
            "cefr_level": "A2",
        },
        {
            "sentence": "He ran ___ than his brother.",
            "options": ["faster", "fast", "fastest", "more fast"],
            "correct_answer": "faster",
            "grammar_tip": "Comparative of short adjectives/adverbs: add -er.",
            "cefr_level": "A2",
        },
        {
            "sentence": "I will call you ___ I arrive.",
            "options": ["when", "while", "during", "since"],
            "correct_answer": "when",
            "grammar_tip": "Time clauses: use 'when' + present simple for future events.",
            "cefr_level": "A2",
        },
        {
            "sentence": "We ___ going to buy a new car next month.",
            "options": ["are", "is", "am", "were"],
            "correct_answer": "are",
            "grammar_tip": "Be going to: We are going to (future plan).",
            "cefr_level": "A2",
        },
        {
            "sentence": "___ did you go on holiday last summer?",
            "options": ["Where", "When", "What", "Who"],
            "correct_answer": "Where",
            "grammar_tip": "'Where' asks about a place.",
            "cefr_level": "A2",
        },
    ],
    "B1": [
        {
            "sentence": "I ___ never been to Japan.",
            "options": ["have", "has", "had", "did"],
            "correct_answer": "have",
            "grammar_tip": "Present Perfect: have/has + past participle. 'Never' is common with PP.",
            "cefr_level": "B1",
        },
        {
            "sentence": "She ___ just finished her project.",
            "options": ["has", "have", "had", "did"],
            "correct_answer": "has",
            "grammar_tip": "Present Perfect: He/She/It has + past participle.",
            "cefr_level": "B1",
        },
        {
            "sentence": "They ___ lived here since 2010.",
            "options": ["have", "has", "had", "did"],
            "correct_answer": "have",
            "grammar_tip": "Use Present Perfect with 'since' (a point in time).",
            "cefr_level": "B1",
        },
        {
            "sentence": "You ___ wear a seatbelt — it's the law.",
            "options": ["must", "might", "could", "would"],
            "correct_answer": "must",
            "grammar_tip": "'Must' expresses strong obligation or necessity.",
            "cefr_level": "B1",
        },
        {
            "sentence": "She ___ speak three languages fluently.",
            "options": ["can", "must", "should", "would"],
            "correct_answer": "can",
            "grammar_tip": "'Can' expresses ability.",
            "cefr_level": "B1",
        },
        {
            "sentence": "You ___ study harder if you want to pass.",
            "options": ["should", "would", "might", "can"],
            "correct_answer": "should",
            "grammar_tip": "'Should' gives advice or recommendation.",
            "cefr_level": "B1",
        },
        {
            "sentence": "He ___ have been working all day — he looks exhausted.",
            "options": ["must", "can", "should", "would"],
            "correct_answer": "must",
            "grammar_tip": "'Must have + PP' = strong deduction about the past.",
            "cefr_level": "B1",
        },
        {
            "sentence": "How long ___ you known her?",
            "options": ["have", "has", "had", "did"],
            "correct_answer": "have",
            "grammar_tip": "Present Perfect question: How long have you...?",
            "cefr_level": "B1",
        },
        {
            "sentence": "I ___ already eaten, thank you.",
            "options": ["have", "had", "has", "did"],
            "correct_answer": "have",
            "grammar_tip": "Present Perfect with 'already': have/has + already + PP.",
            "cefr_level": "B1",
        },
        {
            "sentence": "We ___ finish this project by Friday.",
            "options": ["need to", "needs to", "needed to", "need"],
            "correct_answer": "need to",
            "grammar_tip": "'Need to' expresses necessity (We = plural, no -s).",
            "cefr_level": "B1",
        },
        {
            "sentence": "Have you ___ seen such a beautiful sunset?",
            "options": ["ever", "never", "already", "yet"],
            "correct_answer": "ever",
            "grammar_tip": "'Ever' in PP questions = at any time in your life.",
            "cefr_level": "B1",
        },
        {
            "sentence": "She ___ not come tomorrow — she has a fever.",
            "options": ["might", "can", "shall", "must"],
            "correct_answer": "might",
            "grammar_tip": "'Might' expresses possibility (less certain than 'may').",
            "cefr_level": "B1",
        },
        {
            "sentence": "He has been learning English ___ five years.",
            "options": ["for", "since", "during", "from"],
            "correct_answer": "for",
            "grammar_tip": "Use 'for' with duration; 'since' with a starting point.",
            "cefr_level": "B1",
        },
    ],
    "B2": [
        {
            "sentence": "The letter ___ by the manager yesterday.",
            "options": ["was signed", "signed", "has signed", "is signed"],
            "correct_answer": "was signed",
            "grammar_tip": "Past Passive: was/were + past participle.",
            "cefr_level": "B2",
        },
        {
            "sentence": "This bridge ___ in the 19th century.",
            "options": ["was built", "built", "has built", "is built"],
            "correct_answer": "was built",
            "grammar_tip": "Past Passive singular subject: was + past participle.",
            "cefr_level": "B2",
        },
        {
            "sentence": "If I ___ more time, I would travel the world.",
            "options": ["had", "have", "will have", "having"],
            "correct_answer": "had",
            "grammar_tip": "2nd Conditional: If + past simple, would + base verb.",
            "cefr_level": "B2",
        },
        {
            "sentence": "If she ___ studied harder, she would have passed the exam.",
            "options": ["had", "has", "would", "did"],
            "correct_answer": "had",
            "grammar_tip": "3rd Conditional: If + had + PP, would have + PP.",
            "cefr_level": "B2",
        },
        {
            "sentence": "New policies ___ being introduced next month.",
            "options": ["are", "is", "were", "has been"],
            "correct_answer": "are",
            "grammar_tip": "Present Continuous Passive: am/is/are + being + PP.",
            "cefr_level": "B2",
        },
        {
            "sentence": "The results have ___ yet been announced.",
            "options": ["not", "never", "already", "just"],
            "correct_answer": "not",
            "grammar_tip": "Passive Present Perfect with 'yet': have not + been + PP.",
            "cefr_level": "B2",
        },
        {
            "sentence": "If I were you, I ___ take that job offer.",
            "options": ["would", "will", "could", "should"],
            "correct_answer": "would",
            "grammar_tip": "2nd Conditional advice: If I were you, I would...",
            "cefr_level": "B2",
        },
        {
            "sentence": "A new hospital ___ built in our city right now.",
            "options": ["is being", "is be", "was being", "has been"],
            "correct_answer": "is being",
            "grammar_tip": "Present Continuous Passive: is/are + being + PP.",
            "cefr_level": "B2",
        },
        {
            "sentence": "Unless you hurry, you ___ miss the train.",
            "options": ["will", "would", "might", "could"],
            "correct_answer": "will",
            "grammar_tip": "'Unless' = if not. Use present simple + will in main clause.",
            "cefr_level": "B2",
        },
        {
            "sentence": "The package ___ delivered by noon tomorrow.",
            "options": ["will be", "is", "was", "has been"],
            "correct_answer": "will be",
            "grammar_tip": "Future Passive: will be + past participle.",
            "cefr_level": "B2",
        },
        {
            "sentence": "She ___ have warned us if she had known.",
            "options": ["would", "will", "could", "can"],
            "correct_answer": "would",
            "grammar_tip": "3rd Conditional result clause: would have + PP.",
            "cefr_level": "B2",
        },
        {
            "sentence": "The experiment ___ conducted under strict conditions.",
            "options": ["was", "is", "has", "did"],
            "correct_answer": "was",
            "grammar_tip": "Past Passive: was + past participle.",
            "cefr_level": "B2",
        },
        {
            "sentence": "Provided that you ___ hard, you will succeed.",
            "options": ["work", "worked", "will work", "working"],
            "correct_answer": "work",
            "grammar_tip": "'Provided that' acts like 'if': use present simple for future.",
            "cefr_level": "B2",
        },
    ],
}

# ── Grammar Quiz Question Bank ────────────────────────────────────────────────
# Separate from FILL_BLANK_BANK. Organized by CEFR level and grammar topic.
# Topics per level:
#   A1 → present_simple, to_be
#   A2 → past_simple, future
#   B1 → present_perfect, modals
#   B2 → passive, conditional
#
# Each entry: question (str), options (4), correct_answer (str),
#             explanation, topic, cefr_level

GRAMMAR_QUIZ_BANK: dict = {
    "A1": [
        {
            "question": "She ___ a teacher.",
            "options": ["is", "are", "am", "be"],
            "correct_answer": "is",
            "explanation": "'She' is 3rd person singular → use 'is'.",
            "topic": "to_be",
            "cefr_level": "A1",
        },
        {
            "question": "There ___ two cats in the garden.",
            "options": ["are", "is", "am", "be"],
            "correct_answer": "are",
            "explanation": "'Two cats' is plural → 'are'.",
            "topic": "to_be",
            "cefr_level": "A1",
        },
        {
            "question": "I ___ a student.",
            "options": ["am", "is", "are", "be"],
            "correct_answer": "am",
            "explanation": "With 'I', always use 'am'.",
            "topic": "to_be",
            "cefr_level": "A1",
        },
        {
            "question": "They ___ from France.",
            "options": ["are", "is", "am", "been"],
            "correct_answer": "are",
            "explanation": "'They' is plural → 'are'.",
            "topic": "to_be",
            "cefr_level": "A1",
        },
        {
            "question": "She ___ to school every day.",
            "options": ["goes", "go", "going", "gone"],
            "correct_answer": "goes",
            "explanation": "3rd person singular Present Simple: add -s/-es to the verb.",
            "topic": "present_simple",
            "cefr_level": "A1",
        },
        {
            "question": "___ you like coffee?",
            "options": ["Do", "Does", "Did", "Are"],
            "correct_answer": "Do",
            "explanation": "Yes/No questions with 'you' → Do + you + base verb?",
            "topic": "present_simple",
            "cefr_level": "A1",
        },
        {
            "question": "He doesn't ___ pizza.",
            "options": ["like", "likes", "liked", "liking"],
            "correct_answer": "like",
            "explanation": "After 'doesn't', use the bare infinitive (base form).",
            "topic": "present_simple",
            "cefr_level": "A1",
        },
        {
            "question": "___ is your name?",
            "options": ["What", "Where", "Who", "Why"],
            "correct_answer": "What",
            "explanation": "'What' asks for information about a thing or fact.",
            "topic": "present_simple",
            "cefr_level": "A1",
        },
        {
            "question": "I have ___ apple.",
            "options": ["an", "a", "the", "—"],
            "correct_answer": "an",
            "explanation": "'Apple' starts with a vowel sound → use 'an'.",
            "topic": "to_be",
            "cefr_level": "A1",
        },
        {
            "question": "We ___ happy today.",
            "options": ["are", "is", "am", "be"],
            "correct_answer": "are",
            "explanation": "'We' is plural → 'are'.",
            "topic": "to_be",
            "cefr_level": "A1",
        },
        {
            "question": "He ___ football every Saturday.",
            "options": ["plays", "play", "playing", "played"],
            "correct_answer": "plays",
            "explanation": "He/She/It + verb + -s in Present Simple.",
            "topic": "present_simple",
            "cefr_level": "A1",
        },
        {
            "question": "This is ___ book.",
            "options": ["a", "an", "the", "—"],
            "correct_answer": "a",
            "explanation": "'Book' starts with a consonant sound → 'a'.",
            "topic": "to_be",
            "cefr_level": "A1",
        },
    ],
    "A2": [
        {
            "question": "She ___ her homework yesterday.",
            "options": ["did", "do", "does", "done"],
            "correct_answer": "did",
            "explanation": "'Yesterday' signals Past Simple; auxiliary for questions/negatives is 'did'.",
            "topic": "past_simple",
            "cefr_level": "A2",
        },
        {
            "question": "I ___ to Paris next week.",
            "options": ["am going", "go", "went", "gone"],
            "correct_answer": "am going",
            "explanation": "'Next week' = future plan → 'am going to'.",
            "topic": "future",
            "cefr_level": "A2",
        },
        {
            "question": "She is ___ than her sister.",
            "options": ["taller", "tall", "tallest", "most tall"],
            "correct_answer": "taller",
            "explanation": "Comparing two people → comparative form: adjective + -er.",
            "topic": "past_simple",
            "cefr_level": "A2",
        },
        {
            "question": "I ___ watch TV when I was young.",
            "options": ["used to", "use to", "am used to", "would"],
            "correct_answer": "used to",
            "explanation": "'Used to' expresses a past habit that no longer happens.",
            "topic": "past_simple",
            "cefr_level": "A2",
        },
        {
            "question": "This is ___ book I told you about.",
            "options": ["the", "a", "an", "—"],
            "correct_answer": "the",
            "explanation": "'The' is used for specific items previously mentioned.",
            "topic": "past_simple",
            "cefr_level": "A2",
        },
        {
            "question": "___ you at the party last night?",
            "options": ["Were", "Was", "Are", "Did"],
            "correct_answer": "Were",
            "explanation": "Past of 'to be' with 'you' → were.",
            "topic": "past_simple",
            "cefr_level": "A2",
        },
        {
            "question": "It's the ___ movie I've ever seen.",
            "options": ["best", "better", "good", "more good"],
            "correct_answer": "best",
            "explanation": "Superlative of 'good' is 'best' (irregular).",
            "topic": "past_simple",
            "cefr_level": "A2",
        },
        {
            "question": "I will call you ___ I arrive.",
            "options": ["when", "while", "during", "since"],
            "correct_answer": "when",
            "explanation": "'When' introduces a time clause; use present simple for future.",
            "topic": "future",
            "cefr_level": "A2",
        },
        {
            "question": "She ___ going to start a new job next month.",
            "options": ["is", "are", "am", "be"],
            "correct_answer": "is",
            "explanation": "'She' (3rd person singular) → is going to.",
            "topic": "future",
            "cefr_level": "A2",
        },
        {
            "question": "He ___ the window — it was cold.",
            "options": ["closed", "close", "closing", "closes"],
            "correct_answer": "closed",
            "explanation": "Regular Past Simple: base verb + -d/-ed.",
            "topic": "past_simple",
            "cefr_level": "A2",
        },
        {
            "question": "We ___ going to visit our grandparents.",
            "options": ["are", "is", "am", "be"],
            "correct_answer": "are",
            "explanation": "'We' (plural) → are going to.",
            "topic": "future",
            "cefr_level": "A2",
        },
    ],
    "B1": [
        {
            "question": "I ___ him since last Monday.",
            "options": ["haven't seen", "didn't see", "don't see", "wasn't seeing"],
            "correct_answer": "haven't seen",
            "explanation": "'Since' triggers Present Perfect → 'haven't seen'.",
            "topic": "present_perfect",
            "cefr_level": "B1",
        },
        {
            "question": "If I ___ more time, I would study harder.",
            "options": ["had", "have", "will have", "having"],
            "correct_answer": "had",
            "explanation": "2nd Conditional: If + past simple → would + base verb.",
            "topic": "modals",
            "cefr_level": "B1",
        },
        {
            "question": "The report ___ by the manager yesterday.",
            "options": ["was written", "wrote", "has written", "is written"],
            "correct_answer": "was written",
            "explanation": "'Yesterday' + passive → Past Passive: was + PP.",
            "topic": "present_perfect",
            "cefr_level": "B1",
        },
        {
            "question": "She asked me ___ I had finished.",
            "options": ["if", "whether or not", "what", "that"],
            "correct_answer": "if",
            "explanation": "Reported yes/no question: asked if/whether + subject + verb.",
            "topic": "modals",
            "cefr_level": "B1",
        },
        {
            "question": "By the time we arrived, they ___ already left.",
            "options": ["had", "have", "were", "did"],
            "correct_answer": "had",
            "explanation": "Past Perfect: action completed before another past action.",
            "topic": "present_perfect",
            "cefr_level": "B1",
        },
        {
            "question": "You ___ smoke here — it's not allowed.",
            "options": ["mustn't", "must", "should", "needn't"],
            "correct_answer": "mustn't",
            "explanation": "'Mustn't' expresses prohibition.",
            "topic": "modals",
            "cefr_level": "B1",
        },
        {
            "question": "I remember ___ seen that film before.",
            "options": ["having", "to have", "have", "to having"],
            "correct_answer": "having",
            "explanation": "Remember + -ing = memory of a past action.",
            "topic": "present_perfect",
            "cefr_level": "B1",
        },
        {
            "question": "It's time they ___ the problem.",
            "options": ["fixed", "fix", "will fix", "are fixing"],
            "correct_answer": "fixed",
            "explanation": "'It's time + subject + past simple' means it should happen now.",
            "topic": "modals",
            "cefr_level": "B1",
        },
        {
            "question": "She ___ to have more patience.",
            "options": ["ought", "should", "must", "can"],
            "correct_answer": "ought",
            "explanation": "'Ought to' expresses moral obligation or advice.",
            "topic": "modals",
            "cefr_level": "B1",
        },
        {
            "question": "Have you ever ___ sushi?",
            "options": ["eaten", "eat", "ate", "eating"],
            "correct_answer": "eaten",
            "explanation": "Present Perfect: have/has + past participle.",
            "topic": "present_perfect",
            "cefr_level": "B1",
        },
        {
            "question": "He ___ be a doctor — he's always in a white coat.",
            "options": ["must", "can", "should", "would"],
            "correct_answer": "must",
            "explanation": "'Must' for logical deduction: I'm sure he is a doctor.",
            "topic": "modals",
            "cefr_level": "B1",
        },
    ],
    "B2": [
        {
            "question": "Had I known, I ___ helped you.",
            "options": ["would have", "will have", "could", "had"],
            "correct_answer": "would have",
            "explanation": "3rd Conditional with inversion: Had I known... would have + PP.",
            "topic": "conditional",
            "cefr_level": "B2",
        },
        {
            "question": "The car needs ___.",
            "options": ["repairing", "to repair", "being repaired", "repaired"],
            "correct_answer": "repairing",
            "explanation": "'Need + -ing' carries a passive meaning.",
            "topic": "passive",
            "cefr_level": "B2",
        },
        {
            "question": "Rarely ___ such a beautiful sunset.",
            "options": ["have I seen", "I had seen", "I have seen", "had I seen"],
            "correct_answer": "have I seen",
            "explanation": "Negative adverb 'Rarely' at the front requires subject-auxiliary inversion.",
            "topic": "passive",
            "cefr_level": "B2",
        },
        {
            "question": "He is said ___ a genius.",
            "options": ["to be", "being", "to have been", "that he is"],
            "correct_answer": "to be",
            "explanation": "Passive reporting: is said/believed/thought + to-infinitive.",
            "topic": "passive",
            "cefr_level": "B2",
        },
        {
            "question": "If I ___ rich, I would buy a yacht.",
            "options": ["were", "was", "am", "be"],
            "correct_answer": "were",
            "explanation": "2nd Conditional: 'If I were' (formal/written English uses 'were').",
            "topic": "conditional",
            "cefr_level": "B2",
        },
        {
            "question": "The new policy ___ introduced last week.",
            "options": ["was", "is", "has", "did"],
            "correct_answer": "was",
            "explanation": "Past Passive: was + past participle.",
            "topic": "passive",
            "cefr_level": "B2",
        },
        {
            "question": "Unless it ___ rain, we'll have a picnic.",
            "options": ["doesn't", "don't", "won't", "didn't"],
            "correct_answer": "doesn't",
            "explanation": "'Unless' = if not. Use present simple in the unless-clause.",
            "topic": "conditional",
            "cefr_level": "B2",
        },
        {
            "question": "By next year, the bridge ___ completed.",
            "options": ["will have been", "will be", "has been", "is"],
            "correct_answer": "will have been",
            "explanation": "Future Perfect Passive: will have been + past participle.",
            "topic": "passive",
            "cefr_level": "B2",
        },
        {
            "question": "I wish I ___ harder when I was at school.",
            "options": ["had studied", "studied", "have studied", "would study"],
            "correct_answer": "had studied",
            "explanation": "'I wish + Past Perfect' expresses regret about the past.",
            "topic": "conditional",
            "cefr_level": "B2",
        },
        {
            "question": "The project ___ being reviewed by the committee.",
            "options": ["is", "are", "was", "has"],
            "correct_answer": "is",
            "explanation": "Present Continuous Passive: is/are + being + PP.",
            "topic": "passive",
            "cefr_level": "B2",
        },
        {
            "question": "Supposing you ___ a million dollars, what would you do?",
            "options": ["won", "win", "will win", "winning"],
            "correct_answer": "won",
            "explanation": "'Supposing/Suppose + past simple' opens a 2nd Conditional.",
            "topic": "conditional",
            "cefr_level": "B2",
        },
    ],
}

# ── Auto-seed helper ───────────────────────────────────────────────────────────

_seed_done = False  # In-process flag to avoid re-seeding on every request


async def _ensure_seeded(db: AsyncSession) -> None:
    """Seed the game_words table if it is empty (runs at most once per process)."""
    global _seed_done
    if _seed_done:
        return

    count_result = await db.execute(select(func.count()).select_from(GameWord))
    count = count_result.scalar() or 0
    if count > 0:
        _seed_done = True
        return

    logger.info("game_words table is empty — seeding initial word set...")
    for w in GAME_WORDS_SEED:
        db.add(GameWord(**w))
    await db.commit()
    logger.info(f"Seeded {len(GAME_WORDS_SEED)} game words.")
    _seed_done = True


# ============================================================================
# Game 1: Word Scramble
# ============================================================================

@router.get("/word-scramble")
async def get_word_scramble(
    level: str = Query("A1", description="CEFR level (A1-C2)"),
    count: int = Query(10, ge=3, le=20, description="Number of words to return"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Get scrambled words for the Word Scramble game.

    Queries game_words filtered by CEFR level. Each word's letters are randomly
    shuffled so the player must reorder them to spell the correct word.

    Returns words with word_id, shuffled_letters, hint, definition, xp_value,
    and cefr_level.
    """
    await _ensure_seeded(db)

    result = await db.execute(
        select(GameWord).where(GameWord.cefr_level == level)
    )
    words = result.scalars().all()

    if not words:
        # Graceful fallback: return words from any level
        result = await db.execute(select(GameWord).limit(count + 5))
        words = result.scalars().all()

    selected = random.sample(words, min(count, len(words)))

    items: List[dict] = []
    for w in selected:
        letters = list(w.word.upper())
        shuffled = letters.copy()
        # Guarantee letters are reordered (up to 20 attempts)
        attempts = 0
        while shuffled == letters and len(letters) > 1 and attempts < 20:
            random.shuffle(shuffled)
            attempts += 1

        items.append({
            "word_id": str(w.id),
            "word": w.word,
            "shuffled_letters": shuffled,
            "hint": w.hint,
            "definition": w.definition,
            "xp_value": w.xp_value,
            "cefr_level": w.cefr_level,
        })

    return {
        "game": "word_scramble",
        "cefr_level": level,
        "timer_seconds": TIMER_BY_LEVEL.get(level, 60),
        "words": items,
        "total": len(items),
    }


# ============================================================================
# Game 2: Matching
# ============================================================================

@router.get("/matching")
async def get_matching_game(
    level: str = Query("A1", description="CEFR level (A1-C2)"),
    count: int = Query(6, description="Number of pairs: 4, 6, or 8"),
    variant: str = Query("definition", description="Match type: definition | synonym | vietnamese"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Get word pairs for the Matching game.

    The player connects words in the left column to their matching
    definition / synonym / Vietnamese translation in the right column.

    Both columns are shuffled independently so they are never aligned.
    The response includes the ground-truth pairs list for client-side validation.
    """
    await _ensure_seeded(db)

    # Clamp to supported pair counts
    if count not in (4, 6, 8):
        count = 6

    result = await db.execute(
        select(GameWord).where(GameWord.cefr_level == level)
    )
    all_words = result.scalars().all()

    if not all_words:
        result = await db.execute(select(GameWord))
        all_words = result.scalars().all()

    # Filter to words that have a valid value for the chosen variant
    valid: List[GameWord] = []
    for w in all_words:
        if variant == "synonym" and w.synonyms and len(w.synonyms) > 0:
            valid.append(w)
        elif variant == "vietnamese" and w.vietnamese_translation:
            valid.append(w)
        else:
            # For 'definition' variant, or if we need a fallback
            valid.append(w)

    # FIX: Graceful fallback if no words found for specific variant (e.g., no synonyms in DB)
    if not valid:
        valid = all_words  # Fallback to definitions
        variant = "definition"

    selected = random.sample(valid, min(count, len(valid)))

    pairs: List[dict] = []
    for w in selected:
        if variant == "synonym" and w.synonyms and len(w.synonyms) > 0:
            match_text = w.synonyms[0]
        elif variant == "vietnamese" and w.vietnamese_translation:
            match_text = w.vietnamese_translation
        else:
            match_text = w.definition

        pairs.append({
            "word_id": str(w.id),
            "word": w.word,
            "match_text": match_text,
            "variant": variant,
        })

    # Shuffle both columns independently
    words_column = [p["word"] for p in pairs]
    definitions_column = [p["match_text"] for p in pairs]
    random.shuffle(words_column)
    random.shuffle(definitions_column)

    timer = {"A1": 60, "A2": 60, "B1": 45, "B2": 45, "C1": 30, "C2": 30}.get(level, 45)

    return {
        "game": "matching",
        "cefr_level": level,
        "variant": variant,
        "timer_seconds": timer,
        "pairs": pairs,                        # Ground-truth pairing for validation
        "words_column": words_column,
        "definitions_column": definitions_column,
        "total_pairs": len(pairs),
    }


# ============================================================================
# Game 3: Spelling Bee
# ============================================================================

@router.get("/spelling-bee")
async def get_spelling_bee(
    level: str = Query("A1", description="CEFR level (A1-C2)"),
    count: int = Query(8, ge=3, le=15, description="Number of words"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Get words for the Spelling Bee game.

    The player hears the word spoken (TTS is handled client-side or via the
    separate AI service) and must type the correct spelling.

    audio_url is always null — TTS pronunciation is generated at the client
    or via the AI service's /tts endpoint directly.

    Returns word_id, word, ipa_pronunciation, definition, example_sentence,
    xp_value, and audio_url.
    """
    await _ensure_seeded(db)

    result = await db.execute(
        select(GameWord).where(GameWord.cefr_level == level)
    )
    words = result.scalars().all()

    if not words:
        result = await db.execute(select(GameWord))
        words = result.scalars().all()

    selected = random.sample(words, min(count, len(words)))

    items: List[dict] = []
    for w in selected:
        items.append({
            "word_id": str(w.id),
            "word": w.word,
            "ipa_pronunciation": w.ipa_pronunciation,
            "definition": w.definition,
            "example_sentence": w.example_sentence,
            "xp_value": w.xp_value,
            "audio_url": None,
        })

    return {
        "game": "spelling_bee",
        "cefr_level": level,
        "timer_seconds": TIMER_BY_LEVEL.get(level, 90),
        "words": items,
        "total": len(items),
    }


# ============================================================================
# Game 4: Hangman
# ============================================================================

@router.get("/hangman")
async def get_hangman_word(
    level: str = Query("A1", description="CEFR level (A1-C2)"),
    category: Optional[str] = Query(None, description="Optional category filter"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Get a single random word for the Hangman game.

    Queries game_words filtered by CEFR level (and optionally category).
    Falls back gracefully to any level when no matching words are found,
    and as a final resort uses the hardcoded HANGMAN_FALLBACK_WORDS list
    when the database is empty.

    Returns word_id, word, category, hint, definition, letter_count,
    xp_value, and cefr_level.
    """
    await _ensure_seeded(db)

    query = select(GameWord).where(GameWord.cefr_level == level)
    if category:
        query = query.where(GameWord.category == category)

    result = await db.execute(query)
    words = result.scalars().all()

    # Widen search: drop category filter
    if not words and category:
        result = await db.execute(
            select(GameWord).where(GameWord.cefr_level == level)
        )
        words = result.scalars().all()

    # Widen further: any level
    if not words:
        base_query = select(GameWord)
        if category:
            base_query = base_query.where(GameWord.category == category)
        result = await db.execute(base_query)
        words = result.scalars().all()

    if words:
        word_obj = random.choice(words)
        return {
            "word_id": str(word_obj.id),
            "word": word_obj.word,
            "category": word_obj.category,
            "hint": word_obj.hint,
            "definition": word_obj.definition,
            "letter_count": word_obj.letter_count,
            "xp_value": word_obj.xp_value,
            "cefr_level": word_obj.cefr_level,
        }

    # Final fallback: hardcoded minimal word set
    matching_fallback = [
        w for w in HANGMAN_FALLBACK_WORDS if w["cefr_level"] == level
    ]
    pool = matching_fallback if matching_fallback else HANGMAN_FALLBACK_WORDS
    word_obj = random.choice(pool)

    return {
        "word_id": str(uuid.uuid4()),  # Ephemeral ID for fallback words
        "word": word_obj["word"],
        "category": word_obj["category"],
        "hint": word_obj["hint"],
        "definition": word_obj["definition"],
        "letter_count": word_obj["letter_count"],
        "xp_value": word_obj["xp_value"],
        "cefr_level": word_obj["cefr_level"],
    }


# ============================================================================
# Game 5: Fill in the Blank
# ============================================================================

@router.get("/fill-blank")
async def get_fill_blank(
    level: str = Query("A1", description="CEFR level (A1-C2)"),
    count: int = Query(8, ge=3, le=15, description="Number of questions"),
    current_user: User = Depends(get_current_user),
):
    """
    Get fill-in-the-blank questions from the hardcoded grammar question bank.

    Questions are organized by CEFR level:
      A1 → present simple, to be, possessives
      A2 → past simple, going to
      B1 → present perfect, modals
      B2 → passive, conditionals

    Each question has a sentence with a '___' placeholder, four shuffled
    answer choices, the correct answer as a string, and a grammar tip.

    No AI or DB queries needed — fully offline capable.
    """
    # Graceful fallback for unsupported or missing level
    pool = FILL_BLANK_BANK.get(level) or FILL_BLANK_BANK.get("B1", [])

    selected = random.sample(pool, min(count, len(pool)))

    questions: List[dict] = []
    for i, q in enumerate(selected, start=1):
        shuffled_options = q["options"].copy()
        random.shuffle(shuffled_options)

        questions.append({
            "id": i,
            "sentence": q["sentence"],
            "options": shuffled_options,
            "correct_answer": q["correct_answer"],
            "grammar_tip": q["grammar_tip"],
            "cefr_level": q["cefr_level"],
        })

    return {
        "game": "fill_blank",
        "cefr_level": level,
        "timer_seconds_per_question": 15,
        "questions": questions,
        "total": len(questions),
    }


# ============================================================================
# Game 6: Grammar Quiz
# ============================================================================

@router.get("/grammar-quiz")
async def get_grammar_quiz(
    level: str = Query("A1", description="CEFR level (A1-C2)"),
    topic: Optional[str] = Query(None, description="Grammar topic filter (optional)"),
    count: int = Query(10, ge=3, le=15, description="Number of questions"),
    current_user: User = Depends(get_current_user),
):
    """
    Get grammar quiz questions from the hardcoded question bank.

    Questions are organized by CEFR level and grammar topic:
      A1 → present_simple, to_be
      A2 → past_simple, future
      B1 → present_perfect, modals
      B2 → passive, conditional

    When topic is provided, only questions matching that topic are returned.
    Options are shuffled independently on each request.
    correct_answer is returned as a string (not an index).

    No AI or DB queries needed — fully offline capable.
    """
    pool = GRAMMAR_QUIZ_BANK.get(level) or GRAMMAR_QUIZ_BANK.get("B1", [])

    # Filter by topic; fall back to full pool if topic produces no results
    if topic:
        filtered = [q for q in pool if q.get("topic") == topic]
        if filtered:
            pool = filtered

    selected = random.sample(pool, min(count, len(pool)))

    questions: List[dict] = []
    for i, q in enumerate(selected, start=1):
        shuffled_options = q["options"].copy()
        random.shuffle(shuffled_options)

        questions.append({
            "id": i,
            "question": q["question"],
            "options": shuffled_options,
            "correct_answer": q["correct_answer"],
            "explanation": q["explanation"],
            "topic": q["topic"],
            "cefr_level": q["cefr_level"],
        })

    return {
        "game": "grammar_quiz",
        "cefr_level": level,
        "topic": topic or "mixed",
        "timer_seconds_per_question": 12,
        "questions": questions,
        "total": len(questions),
    }


# ============================================================================
# Game Categories Metadata
# ============================================================================

@router.get("/categories")
async def get_game_categories(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get distinct word categories and their word counts from the game_words table."""
    await _ensure_seeded(db)

    result = await db.execute(
        select(GameWord.category, func.count(GameWord.id).label("count"))
        .group_by(GameWord.category)
    )
    rows = result.all()

    return {
        "categories": [
            {
                "id": row.category,
                "label": row.category.replace("_", " ").title(),
                "count": row.count,
            }
            for row in rows
        ]
    }
