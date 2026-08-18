"""Canonical sample data used by the dev-only /admin/seed endpoint."""

from typing import Any

SAMPLE_ACHIEVEMENTS: list[dict[str, Any]] = [
    {"name": "First Steps", "description": "Complete your first lesson",
     "condition_type": "lessons_completed", "condition_value": 1,
     "category": "lessons", "rarity": "common", "xp_reward": 10, "gems_reward": 5},
    {"name": "Week Warrior", "description": "Maintain a 7-day streak",
     "condition_type": "streak_days", "condition_value": 7,
     "category": "streak", "rarity": "rare", "xp_reward": 50, "gems_reward": 20},
    {"name": "Word Collector", "description": "Add 100 words to vocabulary",
     "condition_type": "vocab_count", "condition_value": 100,
     "category": "vocabulary", "rarity": "epic", "xp_reward": 100, "gems_reward": 50},
    {"name": "Social Butterfly", "description": "Follow 10 friends",
     "condition_type": "following_count", "condition_value": 10,
     "category": "social", "rarity": "rare", "xp_reward": 30, "gems_reward": 15},
]

SAMPLE_COURSE_CATEGORIES: list[dict[str, Any]] = [
    {
        "name": "Grammar",
        "slug": "grammar",
        "description": "Master English grammar rules and structures",
        "icon": "📚",
        "color": "#4CAF50",
        "order_index": 1,
    },
    {
        "name": "Vocabulary",
        "slug": "vocabulary",
        "description": "Build practical English vocabulary for daily use",
        "icon": "🧠",
        "color": "#2196F3",
        "order_index": 2,
    },
]

SAMPLE_COURSES: list[dict[str, Any]] = [
    {
        "title": "English Grammar Foundations",
        "description": "Start with core grammar patterns for everyday communication.",
        "language": "en",
        "level": "A1",
        "category_slug": "grammar",
        "tags": ["grammar", "beginner", "fundamentals"],
        "total_xp": 120,
        "estimated_duration": 90,
        "thumbnail_url": "https://images.unsplash.com/photo-1456513080510-7bf3a84b82f8",
        "units": [
            {
                "title": "Present Simple Basics",
                "description": "Build confidence with daily routine sentences.",
                "order_index": 1,
                "background_color": "#1E3A8A",
                "lessons": [
                    {
                        "title": "I/You/We/They + Verb",
                        "description": "Form positive present simple sentences.",
                        "order_index": 1,
                        "estimated_minutes": 12,
                        "xp_reward": 20,
                        "total_exercises": 10,
                        "exercises": [
                            {
                                "id": "ex_g1_1",
                                "type": "multiple_choice",
                                "ui_type": "multiple_choice",
                                "question": "Choose the correct form: 'I ___ coffee every morning.'",
                                "options": [{"id": "0", "text": "drink", "is_correct": True}, {"id": "1", "text": "drinks", "is_correct": False}, {"id": "2", "text": "drinking", "is_correct": False}, {"id": "3", "text": "drunk", "is_correct": False}],
                                "correct_answer": "drink",
                                "explanation": "With I/You/We/They, use the base verb form."
                            },
                            {
                                "id": "ex_g1_2",
                                "type": "true_false",
                                "ui_type": "true_or_false",
                                "question": "True or False: 'They plays football' is grammatically correct.",
                                "options": [{"id": "0", "text": "True", "is_correct": False}, {"id": "1", "text": "False", "is_correct": True}],
                                "correct_answer": "False",
                                "explanation": "'They' is plural and takes the base verb 'play', not 'plays'."
                            },
                            {
                                "id": "ex_g1_3",
                                "type": "fill_blank",
                                "ui_type": "fill_in_the_blank",
                                "question": "Complete the sentence: 'We {blank} in a big city.'",
                                "correct_answer": "live",
                                "explanation": "'We' takes the base verb 'live'."
                            },
                            {
                                "id": "ex_g1_4",
                                "type": "reorder",
                                "ui_type": "arrange_the_sentence",
                                "question": "Arrange: 'day / every / study / they'",
                                "options": [{"id": "0", "text": "they"}, {"id": "1", "text": "study"}, {"id": "2", "text": "every"}, {"id": "3", "text": "day"}],
                                "correct_answer": "they study every day",
                                "explanation": "Subject + Verb + Time expression is the standard structure."
                            },
                            {
                                "id": "ex_g1_5",
                                "type": "translate",
                                "ui_type": "translation_choice",
                                "question": "Choose the translation for: 'Chúng tôi muốn học.'",
                                "options": [{"id": "0", "text": "We want to learn.", "is_correct": True}, {"id": "1", "text": "We wants to learn.", "is_correct": False}, {"id": "2", "text": "We learning.", "is_correct": False}],
                                "correct_answer": "We want to learn.",
                                "explanation": "'Chúng tôi' translates to 'We', which takes the base verb 'want'."
                            },
                            {
                                "id": "ex_g1_6",
                                "type": "fill_blank",
                                "ui_type": "dialogue_completion",
                                "question": "A: Do you speak English? B: Yes, I {blank}.",
                                "correct_answer": "do",
                                "explanation": "Short answer to 'Do you...' is 'I do'."
                            },
                            {
                                "id": "ex_g1_7",
                                "type": "multiple_choice",
                                "ui_type": "collocation_choice",
                                "question": "Complete the phrase: 'They ___ homework together.'",
                                "options": [{"id": "0", "text": "do", "is_correct": True}, {"id": "1", "text": "make", "is_correct": False}],
                                "correct_answer": "do",
                                "explanation": "The collocation is 'do homework'."
                            },
                            {
                                "id": "ex_g1_8",
                                "type": "fill_blank",
                                "ui_type": "dictation",
                                "question": "Listen and write what you hear: '{blank}'",
                                "correct_answer": "We go home",
                                "explanation": "Type the exact words heard in the audio."
                            },
                            {
                                "id": "ex_g1_9",
                                "type": "translate",
                                "ui_type": "speaking_repeat",
                                "question": "Repeat: 'I listen to music.'",
                                "correct_answer": "I listen to music",
                                "explanation": "Record yourself repeating this sentence."
                            },
                            {
                                "id": "ex_g1_10",
                                "type": "multiple_choice",
                                "ui_type": "vocabulary_flashcard",
                                "question": "Learn the card: 'Routine'",
                                # A single "Got it!" option grades itself correct
                                # and pays XP for a tap — the card has to ask.
                                "options": [
                                    {"id": "0", "text": "Việc làm hằng ngày", "is_correct": True},
                                    {"id": "1", "text": "Chuyến đi xa", "is_correct": False},
                                    {"id": "2", "text": "Bữa tiệc bất ngờ", "is_correct": False},
                                    {"id": "3", "text": "Kỳ nghỉ dài", "is_correct": False},
                                ],
                                "correct_answer": "Việc làm hằng ngày",
                                "explanation": "Routine is a sequence of actions regularly followed."
                            }
                        ]
                    },
                    {
                        "title": "He/She/It + Verb-s",
                        "description": "Use third-person singular correctly.",
                        "order_index": 2,
                        "estimated_minutes": 12,
                        "xp_reward": 20,
                        "total_exercises": 10,
                        "exercises": [
                            {
                                "id": "ex_g2_1",
                                "type": "multiple_choice",
                                "ui_type": "multiple_choice",
                                "question": "Choose correct: 'He ___ to school by bus.'",
                                "options": [{"id": "0", "text": "go", "is_correct": False}, {"id": "1", "text": "goes", "is_correct": True}, {"id": "2", "text": "going", "is_correct": False}],
                                "correct_answer": "goes",
                                "explanation": "He/she/it takes verb+s/es."
                            },
                            {
                                "id": "ex_g2_2",
                                "type": "true_false",
                                "ui_type": "true_or_false",
                                "question": "True or False: 'It rain a lot' is correct.",
                                "options": [{"id": "0", "text": "True", "is_correct": False}, {"id": "1", "text": "False", "is_correct": True}],
                                "correct_answer": "False",
                                "explanation": "It should be 'It rains a lot'."
                            },
                            {
                                "id": "ex_g2_3",
                                "type": "fill_blank",
                                "ui_type": "fill_in_the_blank",
                                "question": "Complete: 'She {blank} the piano well.'",
                                "correct_answer": "plays",
                                "explanation": "She requires plays."
                            },
                            {
                                "id": "ex_g2_4",
                                "type": "fill_blank",
                                "ui_type": "grammar_correction",
                                "question": "Correct the error: 'He play tennis.' -> '{blank}'",
                                "correct_answer": "He plays tennis",
                                "explanation": "Add 's' to play."
                            },
                            {
                                "id": "ex_g2_5",
                                "type": "multiple_choice",
                                "ui_type": "image_based_choice",
                                "question": "Choose the image that represents: 'She runs.'",
                                "options": [{"id": "0", "text": "Running", "is_correct": True}, {"id": "1", "text": "Sleeping", "is_correct": False}],
                                "correct_answer": "Running",
                                "explanation": "Select the correct action card."
                            },
                            {
                                "id": "ex_g2_6",
                                "type": "multiple_choice",
                                "ui_type": "listen_and_choose",
                                "question": "Listen and select what he does.",
                                "options": [{"id": "0", "text": "He eats breakfast", "is_correct": True}, {"id": "1", "text": "He plays games", "is_correct": False}],
                                "correct_answer": "He eats breakfast",
                                "explanation": "Audio matches breakfast."
                            },
                            {
                                "id": "ex_g2_7",
                                "type": "translate",
                                "ui_type": "pronunciation_practice",
                                "question": "Practice speaking: 'He plays tennis.'",
                                "correct_answer": "He plays tennis",
                                "explanation": "Evaluate pronunciation of He plays tennis."
                            },
                            {
                                "id": "ex_g2_8",
                                "type": "multiple_choice",
                                "ui_type": "reading_comprehension",
                                "question": "Read and answer: 'Tom is a chef. He works in a restaurant.' Where does Tom work?",
                                "options": [{"id": "0", "text": "restaurant", "is_correct": True}, {"id": "1", "text": "office", "is_correct": False}],
                                "correct_answer": "restaurant",
                                "explanation": "The text states he works in a restaurant."
                            },
                            {
                                "id": "ex_g2_9",
                                "type": "fill_blank",
                                "ui_type": "short_writing_answer",
                                "question": "Write in English: 'Cô ấy nói tiếng Anh.'",
                                "correct_answer": "She speaks English",
                                "explanation": "Translate exactly."
                            },
                            {
                                "id": "ex_g2_10",
                                "type": "matching",
                                "ui_type": "categorization",
                                "question": "Categorize the pronouns: Singular vs Plural",
                                "options": ["he", "they", "Singular", "Plural"],
                                "correct_answer": "he:Singular, they:Plural",
                                "explanation": "He is singular, they is plural."
                            }
                        ]
                    },
                ],
            },
        ],
    },
    {
        "title": "Daily Vocabulary Starter",
        "description": "Learn essential words and phrases for daily life.",
        "language": "en",
        "level": "A1",
        "category_slug": "vocabulary",
        "tags": ["vocabulary", "daily-life", "beginner"],
        "total_xp": 120,
        "estimated_duration": 80,
        "thumbnail_url": "https://images.unsplash.com/photo-1434030216411-0b793f4b4173",
        "units": [
            {
                "title": "Home and Family",
                "description": "Words you use every day at home.",
                "order_index": 1,
                "background_color": "#0F766E",
                "lessons": [
                    {
                        "title": "Family Members",
                        "description": "Describe people in your family.",
                        "order_index": 1,
                        "estimated_minutes": 10,
                        "xp_reward": 20,
                        "total_exercises": 10,
                        "exercises": [
                            {
                                "id": "ex_v1_1",
                                "type": "multiple_choice",
                                "ui_type": "multiple_choice",
                                "question": "Your father's sister is your ___.",
                                "options": [{"id": "0", "text": "aunt", "is_correct": True}, {"id": "1", "text": "uncle", "is_correct": False}],
                                "correct_answer": "aunt",
                                "explanation": "Father's sister is aunt."
                            },
                            {
                                "id": "ex_v1_2",
                                "type": "matching",
                                "ui_type": "match_word_to_meaning",
                                "question": "Match the family words with meanings.",
                                "options": ["father", "mother", "Male parent", "Female parent"],
                                "correct_answer": "father:Male parent, mother:Female parent",
                                "explanation": "Father is male parent, mother is female."
                            },
                            {
                                "id": "ex_v1_3",
                                "type": "fill_blank",
                                "ui_type": "fill_in_the_blank",
                                "question": "Complete: 'My mother's husband is my {blank}.'",
                                "correct_answer": "father",
                                "explanation": "Mother's husband is father."
                            },
                            {
                                "id": "ex_v1_4",
                                "type": "matching",
                                "ui_type": "cognitive_fluidity",
                                "question": "Match: mother, sister",
                                "options": ["mother", "sister", "female parent", "female sibling"],
                                "correct_answer": "mother:female parent, sister:female sibling",
                                "explanation": "Fast match."
                            },
                            {
                                "id": "ex_v1_5",
                                "type": "multiple_choice",
                                "ui_type": "vocabulary_flashcard",
                                "question": "Learn: 'Sibling'",
                                "options": [
                                    {"id": "0", "text": "Anh chị em ruột", "is_correct": True},
                                    {"id": "1", "text": "Cha mẹ", "is_correct": False},
                                    {"id": "2", "text": "Ông bà", "is_correct": False},
                                    {"id": "3", "text": "Hàng xóm", "is_correct": False},
                                ],
                                "correct_answer": "Anh chị em ruột",
                                "explanation": "A sibling is a brother or sister."
                            },
                            {
                                "id": "ex_v1_6",
                                "type": "true_false",
                                "ui_type": "true_or_false",
                                "question": "True or False: 'Cousin' is the child of your aunt or uncle.",
                                "options": [{"id": "0", "text": "True", "is_correct": True}, {"id": "1", "text": "False", "is_correct": False}],
                                "correct_answer": "True",
                                "explanation": "Cousin is child of aunt/uncle."
                            },
                            {
                                "id": "ex_v1_7",
                                "type": "reorder",
                                "ui_type": "arrange_the_sentence",
                                "question": "Arrange: 'my / this / is / brother'",
                                "options": [{"id": "0", "text": "this"}, {"id": "1", "text": "is"}, {"id": "2", "text": "my"}, {"id": "3", "text": "brother"}],
                                "correct_answer": "this is my brother",
                                "explanation": "Sentence structure."
                            },
                            {
                                "id": "ex_v1_8",
                                "type": "translate",
                                "ui_type": "translation_choice",
                                "question": "Translation of: 'Anh trai'",
                                "options": [{"id": "0", "text": "brother", "is_correct": True}, {"id": "1", "text": "sister", "is_correct": False}],
                                "correct_answer": "brother",
                                "explanation": "Anh trai is brother."
                            },
                            {
                                "id": "ex_v1_9",
                                "type": "translate",
                                "ui_type": "speaking_repeat",
                                "question": "Repeat: 'My grandmother is nice.'",
                                "correct_answer": "My grandmother is nice",
                                "explanation": "Practice speaking."
                            },
                            {
                                "id": "ex_v1_10",
                                "type": "fill_blank",
                                "ui_type": "dictation",
                                "question": "Dictation: Listen and write '{blank}'",
                                "correct_answer": "He is my uncle",
                                "explanation": "Type what you hear."
                            }
                        ]
                    },
                    {
                        "title": "Rooms and Objects",
                        "description": "Talk about places and things at home.",
                        "order_index": 2,
                        "estimated_minutes": 10,
                        "xp_reward": 20,
                        "total_exercises": 10,
                        "exercises": [
                            {
                                "id": "ex_v2_1",
                                "type": "multiple_choice",
                                "ui_type": "multiple_choice",
                                "question": "You cook meals in the ___.",
                                "options": [{"id": "0", "text": "kitchen", "is_correct": True}, {"id": "1", "text": "bedroom", "is_correct": False}],
                                "correct_answer": "kitchen",
                                "explanation": "Kitchen is for cooking."
                            },
                            {
                                "id": "ex_v2_2",
                                "type": "matching",
                                "ui_type": "match_word_to_meaning",
                                "question": "Match rooms with objects.",
                                "options": ["bedroom", "kitchen", "bed", "fridge"],
                                "correct_answer": "bedroom:bed, kitchen:fridge",
                                "explanation": "Bed in bedroom, fridge in kitchen."
                            },
                            {
                                "id": "ex_v2_3",
                                "type": "fill_blank",
                                "ui_type": "fill_in_the_blank",
                                "question": "Complete: 'I sleep in my {blank}.'",
                                "correct_answer": "bedroom",
                                "explanation": "Bedroom is for sleeping."
                            },
                            {
                                "id": "ex_v2_4",
                                "type": "true_false",
                                "ui_type": "true_or_false",
                                "question": "True or False: A sofa is typically placed in the living room.",
                                "options": [{"id": "0", "text": "True", "is_correct": True}, {"id": "1", "text": "False", "is_correct": False}],
                                "correct_answer": "True",
                                "explanation": "Sofa in living room."
                            },
                            {
                                "id": "ex_v2_5",
                                "type": "reorder",
                                "ui_type": "arrange_the_sentence",
                                "question": "Arrange: 'in / the / bed / is / bedroom / the'",
                                "options": [{"id": "0", "text": "the"}, {"id": "1", "text": "bed"}, {"id": "2", "text": "is"}, {"id": "3", "text": "in"}, {"id": "4", "text": "the"}, {"id": "5", "text": "bedroom"}],
                                "correct_answer": "the bed is in the bedroom",
                                "explanation": "Correct sentence structure."
                            },
                            {
                                "id": "ex_v2_6",
                                "type": "translate",
                                "ui_type": "translation_choice",
                                "question": "Translation of: 'Phòng tắm'",
                                "options": [{"id": "0", "text": "bathroom", "is_correct": True}, {"id": "1", "text": "garden", "is_correct": False}],
                                "correct_answer": "bathroom",
                                "explanation": "Phòng tắm is bathroom."
                            },
                            {
                                "id": "ex_v2_7",
                                "type": "translate",
                                "ui_type": "speaking_repeat",
                                "question": "Repeat: 'The desk is clean.'",
                                "correct_answer": "The desk is clean",
                                "explanation": "Evaluate pronunciation."
                            },
                            {
                                "id": "ex_v2_8",
                                "type": "fill_blank",
                                "ui_type": "dictation",
                                "question": "Dictation: Listen and write '{blank}'",
                                "correct_answer": "Open the window",
                                "explanation": "Write what you hear."
                            },
                            {
                                "id": "ex_v2_9",
                                "type": "multiple_choice",
                                "ui_type": "image_based_choice",
                                "question": "Select the image that shows a table.",
                                "options": [{"id": "0", "text": "Table", "is_correct": True}, {"id": "1", "text": "Chair", "is_correct": False}],
                                "correct_answer": "Table",
                                "explanation": "Card with table."
                            },
                            {
                                "id": "ex_v2_10",
                                "type": "multiple_choice",
                                "ui_type": "vocabulary_flashcard",
                                "question": "Learn: 'Furnishings'",
                                "options": [
                                    {"id": "0", "text": "Đồ đạc trong phòng", "is_correct": True},
                                    {"id": "1", "text": "Quần áo mùa đông", "is_correct": False},
                                    {"id": "2", "text": "Dụng cụ nhà bếp", "is_correct": False},
                                    {"id": "3", "text": "Cây cảnh ngoài vườn", "is_correct": False},
                                ],
                                "correct_answer": "Đồ đạc trong phòng",
                                "explanation": "Furniture and appliances in a room."
                            }
                        ]
                    },
                ],
            },
        ],
    },
]
