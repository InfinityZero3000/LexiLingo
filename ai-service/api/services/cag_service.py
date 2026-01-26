"""
Content Auto-Generation (CAG) Service

Automatically generates learning content based on:
- User level (A1-C2)
- Error patterns
- Learning history
- Interests/topics

Following architecture.md principles for adaptive learning
"""

import random
from typing import List, Dict, Any, Optional
from datetime import datetime
import logging

logger = logging.getLogger(__name__)


class ContentAutoGenerator:
    """
    Main CAG service for generating adaptive learning content.
    
    Generates:
    - Vocabulary exercises
    - Grammar drills
    - Conversation prompts
    - Reading passages
    - Writing prompts
    - Pronunciation exercises
    """
    
    def __init__(self):
        self.templates = ContentTemplates()
        self.difficulty_adjuster = DifficultyAdjuster()
        self.topic_selector = TopicSelector()
    
    # ============================================================
    # Vocabulary Exercises
    # ============================================================
    
    def generate_vocabulary_exercise(
        self,
        level: str,
        topic: Optional[str] = None,
        count: int = 10,
        error_patterns: Optional[List[str]] = None
    ) -> Dict[str, Any]:
        """
        Generate vocabulary exercise.
        
        Args:
            level: User level (A1-C2)
            topic: Topic (e.g., "daily_life", "business", "travel")
            count: Number of words
            error_patterns: Common errors to focus on
        
        Returns:
            Exercise with words, definitions, examples
        """
        try:
            # Select topic if not provided
            if not topic:
                topic = self.topic_selector.select_topic(level)
            
            # Get vocabulary pool
            vocab_pool = self.templates.get_vocabulary_pool(level, topic)
            
            # Select words
            words = random.sample(vocab_pool, min(count, len(vocab_pool)))
            
            # Create exercise
            exercise = {
                "type": "vocabulary",
                "level": level,
                "topic": topic,
                "instructions": self._get_vocab_instructions(level),
                "words": [
                    {
                        "word": word["word"],
                        "definition": word["definition"],
                        "example": word["example"],
                        "difficulty": word.get("difficulty", level)
                    }
                    for word in words
                ],
                "tasks": [
                    {
                        "task_type": "fill_blank",
                        "sentence": self._create_fill_blank(words[i]),
                        "answer": words[i]["word"]
                    }
                    for i in range(min(5, len(words)))
                ],
                "generated_at": datetime.utcnow().isoformat()
            }
            
            return exercise
            
        except Exception as e:
            logger.error(f"Failed to generate vocabulary exercise: {e}")
            raise
    
    # ============================================================
    # Grammar Drills
    # ============================================================
    
    def generate_grammar_drill(
        self,
        level: str,
        grammar_point: Optional[str] = None,
        error_patterns: Optional[List[str]] = None,
        count: int = 10
    ) -> Dict[str, Any]:
        """
        Generate grammar drill focused on specific grammar point.
        
        Args:
            level: User level
            grammar_point: Specific grammar (e.g., "past_tense", "articles")
            error_patterns: User's common errors
            count: Number of exercises
        
        Returns:
            Grammar drill with exercises
        """
        try:
            # Select grammar point based on errors or level
            if not grammar_point:
                if error_patterns:
                    grammar_point = error_patterns[0]  # Focus on most common error
                else:
                    grammar_point = self._select_grammar_for_level(level)
            
            # Get grammar templates
            templates = self.templates.get_grammar_templates(level, grammar_point)
            
            # Generate exercises
            exercises = []
            for _ in range(count):
                template = random.choice(templates)
                exercise = self._apply_grammar_template(template)
                exercises.append(exercise)
            
            drill = {
                "type": "grammar",
                "level": level,
                "grammar_point": grammar_point,
                "explanation": self._get_grammar_explanation(grammar_point, level),
                "instructions": "Choose the correct form or fill in the blanks",
                "exercises": exercises,
                "tips": self._get_grammar_tips(grammar_point),
                "generated_at": datetime.utcnow().isoformat()
            }
            
            return drill
            
        except Exception as e:
            logger.error(f"Failed to generate grammar drill: {e}")
            raise
    
    # ============================================================
    # Conversation Prompts
    # ============================================================
    
    def generate_conversation_prompt(
        self,
        level: str,
        topic: Optional[str] = None,
        scenario: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Generate conversation prompt for practice.
        
        Args:
            level: User level
            topic: Conversation topic
            scenario: Specific scenario (e.g., "restaurant", "job_interview")
        
        Returns:
            Conversation prompt with role-play scenario
        """
        try:
            # Select scenario
            if not scenario:
                scenario = self.topic_selector.select_scenario(level, topic)
            
            # Get conversation template
            template = self.templates.get_conversation_template(level, scenario)
            
            prompt = {
                "type": "conversation",
                "level": level,
                "scenario": scenario,
                "topic": topic or self._extract_topic(scenario),
                "role_play": {
                    "situation": template["situation"],
                    "your_role": template["user_role"],
                    "ai_role": template["ai_role"],
                    "objectives": template["objectives"]
                },
                "starter_phrases": template["starters"],
                "vocabulary_hints": template["key_vocabulary"],
                "cultural_notes": template.get("cultural_notes", []),
                "generated_at": datetime.utcnow().isoformat()
            }
            
            return prompt
            
        except Exception as e:
            logger.error(f"Failed to generate conversation prompt: {e}")
            raise
    
    # ============================================================
    # Reading Passages
    # ============================================================
    
    def generate_reading_passage(
        self,
        level: str,
        topic: Optional[str] = None,
        length: str = "medium"  # short, medium, long
    ) -> Dict[str, Any]:
        """
        Generate reading passage with comprehension questions.
        
        Args:
            level: User level
            topic: Reading topic
            length: Passage length
        
        Returns:
            Reading passage with questions
        """
        try:
            # Select topic
            if not topic:
                topic = self.topic_selector.select_reading_topic(level)
            
            # Get passage template
            template = self.templates.get_reading_template(level, topic, length)
            
            # Adjust difficulty
            passage_text = self.difficulty_adjuster.adjust_reading(
                template["text"], 
                level
            )
            
            passage = {
                "type": "reading",
                "level": level,
                "topic": topic,
                "length": length,
                "title": template["title"],
                "passage": passage_text,
                "word_count": len(passage_text.split()),
                "comprehension_questions": [
                    {
                        "question": q["question"],
                        "type": q["type"],  # multiple_choice, true_false, short_answer
                        "options": q.get("options"),
                        "answer": q["answer"]
                    }
                    for q in template["questions"]
                ],
                "vocabulary_glossary": template.get("glossary", {}),
                "generated_at": datetime.utcnow().isoformat()
            }
            
            return passage
            
        except Exception as e:
            logger.error(f"Failed to generate reading passage: {e}")
            raise
    
    # ============================================================
    # Writing Prompts
    # ============================================================
    
    def generate_writing_prompt(
        self,
        level: str,
        writing_type: str = "essay",  # essay, email, letter, story
        topic: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Generate writing prompt.
        
        Args:
            level: User level
            writing_type: Type of writing
            topic: Writing topic
        
        Returns:
            Writing prompt with guidelines
        """
        try:
            # Select topic
            if not topic:
                topic = self.topic_selector.select_writing_topic(level, writing_type)
            
            # Get prompt template
            template = self.templates.get_writing_template(level, writing_type, topic)
            
            prompt = {
                "type": "writing",
                "level": level,
                "writing_type": writing_type,
                "topic": topic,
                "prompt": template["prompt"],
                "guidelines": {
                    "word_count": template["word_count"],
                    "structure": template["structure"],
                    "key_points": template["key_points"]
                },
                "sample_phrases": template["sample_phrases"],
                "rubric": {
                    "content": "Relevance and depth",
                    "organization": "Structure and flow",
                    "grammar": "Accuracy",
                    "vocabulary": "Range and appropriateness"
                },
                "generated_at": datetime.utcnow().isoformat()
            }
            
            return prompt
            
        except Exception as e:
            logger.error(f"Failed to generate writing prompt: {e}")
            raise
    
    # ============================================================
    # Pronunciation Exercises
    # ============================================================
    
    def generate_pronunciation_exercise(
        self,
        level: str,
        focus: Optional[str] = None,  # phoneme, stress, intonation
        error_patterns: Optional[List[str]] = None
    ) -> Dict[str, Any]:
        """
        Generate pronunciation exercise.
        
        Args:
            level: User level
            focus: Focus area
            error_patterns: Common pronunciation errors
        
        Returns:
            Pronunciation exercise
        """
        try:
            # Determine focus
            if not focus:
                if error_patterns:
                    focus = self._map_error_to_focus(error_patterns[0])
                else:
                    focus = "phoneme"
            
            # Get pronunciation template
            template = self.templates.get_pronunciation_template(level, focus)
            
            exercise = {
                "type": "pronunciation",
                "level": level,
                "focus": focus,
                "target_sounds": template["target_sounds"],
                "practice_words": template["words"],
                "practice_sentences": template["sentences"],
                "minimal_pairs": template.get("minimal_pairs", []),
                "tips": template["tips"],
                "generated_at": datetime.utcnow().isoformat()
            }
            
            return exercise
            
        except Exception as e:
            logger.error(f"Failed to generate pronunciation exercise: {e}")
            raise
    
    # ============================================================
    # Adaptive Content Generation
    # ============================================================
    
    def generate_personalized_lesson(
        self,
        user_id: str,
        user_level: str,
        error_patterns: List[str],
        interests: List[str],
        learning_history: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Generate personalized lesson based on user profile.
        
        Args:
            user_id: User ID
            user_level: Current level
            error_patterns: Common errors
            interests: User interests
            learning_history: Past performance
        
        Returns:
            Complete personalized lesson
        """
        try:
            # Analyze needs
            focus_areas = self._analyze_needs(error_patterns, learning_history)
            
            # Select topics based on interests
            topic = random.choice(interests) if interests else None
            
            # Generate mixed content
            lesson = {
                "user_id": user_id,
                "level": user_level,
                "lesson_type": "personalized",
                "focus_areas": focus_areas,
                "components": []
            }
            
            # Add grammar if needed
            if "grammar" in focus_areas:
                grammar_drill = self.generate_grammar_drill(
                    user_level,
                    error_patterns[0] if error_patterns else None,
                    error_patterns
                )
                lesson["components"].append(grammar_drill)
            
            # Add vocabulary
            vocab_exercise = self.generate_vocabulary_exercise(
                user_level,
                topic,
                count=8
            )
            lesson["components"].append(vocab_exercise)
            
            # Add conversation
            conversation = self.generate_conversation_prompt(
                user_level,
                topic
            )
            lesson["components"].append(conversation)
            
            # Add reading if level appropriate
            if user_level not in ["A1"]:
                reading = self.generate_reading_passage(
                    user_level,
                    topic,
                    length="short" if user_level in ["A2", "B1"] else "medium"
                )
                lesson["components"].append(reading)
            
            lesson["generated_at"] = datetime.utcnow().isoformat()
            lesson["estimated_duration_minutes"] = len(lesson["components"]) * 10
            
            return lesson
            
        except Exception as e:
            logger.error(f"Failed to generate personalized lesson: {e}")
            raise
    
    # ============================================================
    # Helper Methods
    # ============================================================
    
    def _get_vocab_instructions(self, level: str) -> str:
        """Get instructions based on level."""
        instructions = {
            "A1": "Learn these basic words. Read the definitions and examples.",
            "A2": "Study these words. Try to use them in your own sentences.",
            "B1": "Master these words. Note the usage context.",
            "B2": "Learn these advanced words. Pay attention to collocations.",
            "C1": "Study these sophisticated terms. Note nuances in meaning.",
            "C2": "Master these expressions. Focus on register and connotation."
        }
        return instructions.get(level, instructions["B1"])
    
    def _create_fill_blank(self, word: Dict[str, str]) -> str:
        """Create fill-in-the-blank from example."""
        example = word["example"]
        word_text = word["word"]
        return example.replace(word_text, "______", 1)
    
    def _select_grammar_for_level(self, level: str) -> str:
        """Select appropriate grammar point for level."""
        grammar_map = {
            "A1": "present_simple",
            "A2": "past_simple",
            "B1": "present_perfect",
            "B2": "conditionals",
            "C1": "subjunctive",
            "C2": "inversion"
        }
        return grammar_map.get(level, "present_perfect")
    
    def _apply_grammar_template(self, template: Dict) -> Dict:
        """Apply grammar template to create exercise."""
        return {
            "sentence": template["sentence"],
            "options": template.get("options", []),
            "correct_answer": template["answer"],
            "explanation": template.get("explanation", "")
        }
    
    def _get_grammar_explanation(self, grammar_point: str, level: str) -> str:
        """Get explanation for grammar point."""
        # This would be loaded from templates
        return f"Explanation of {grammar_point} for {level} level"
    
    def _get_grammar_tips(self, grammar_point: str) -> List[str]:
        """Get tips for grammar point."""
        return [
            "Pay attention to the tense markers",
            "Check subject-verb agreement",
            "Consider the context"
        ]
    
    def _extract_topic(self, scenario: str) -> str:
        """Extract topic from scenario."""
        return scenario.split("_")[0]
    
    def _map_error_to_focus(self, error: str) -> str:
        """Map error type to pronunciation focus."""
        mapping = {
            "th_sound": "phoneme",
            "word_stress": "stress",
            "question_intonation": "intonation"
        }
        return mapping.get(error, "phoneme")
    
    def _analyze_needs(
        self,
        error_patterns: List[str],
        learning_history: Dict[str, Any]
    ) -> List[str]:
        """Analyze user needs from errors and history."""
        needs = []
        
        if error_patterns:
            # Grammar errors indicate need for grammar focus
            if any("tense" in err or "agreement" in err for err in error_patterns):
                needs.append("grammar")
            
            # Low vocabulary indicates vocab focus
            if "vocabulary" in str(learning_history):
                needs.append("vocabulary")
        
        # Default focus
        if not needs:
            needs = ["vocabulary", "grammar", "conversation"]
        
        return needs


class ContentTemplates:
    """Template storage and retrieval."""
    
    def get_vocabulary_pool(self, level: str, topic: str) -> List[Dict]:
        """Get vocabulary pool for level and topic."""
        # In production, this would load from database
        return [
            {
                "word": "study",
                "definition": "to learn about a subject",
                "example": "I study English every day.",
                "difficulty": "A1"
            },
            {
                "word": "practice",
                "definition": "to do something repeatedly to improve",
                "example": "She practices speaking with native speakers.",
                "difficulty": "A2"
            },
            # More words...
        ]
    
    def get_grammar_templates(self, level: str, grammar_point: str) -> List[Dict]:
        """Get grammar templates."""
        return [
            {
                "sentence": "I _____ to school yesterday.",
                "options": ["go", "went", "gone", "going"],
                "answer": "went",
                "explanation": "Use past simple for completed past actions"
            }
        ]
    
    def get_conversation_template(self, level: str, scenario: str) -> Dict:
        """Get conversation template."""
        return {
            "situation": "Ordering food at a restaurant",
            "user_role": "Customer",
            "ai_role": "Waiter",
            "objectives": ["Order a meal", "Ask about menu items", "Make special requests"],
            "starters": ["Hello, I'd like to order...", "What do you recommend?"],
            "key_vocabulary": ["menu", "order", "recommend", "allergic"]
        }
    
    def get_reading_template(self, level: str, topic: str, length: str) -> Dict:
        """Get reading template."""
        return {
            "title": "A Day in the Life",
            "text": "Sample reading passage...",
            "questions": [
                {
                    "question": "What is the main idea?",
                    "type": "multiple_choice",
                    "options": ["A", "B", "C", "D"],
                    "answer": "B"
                }
            ]
        }
    
    def get_writing_template(self, level: str, writing_type: str, topic: str) -> Dict:
        """Get writing template."""
        return {
            "prompt": "Write about your daily routine",
            "word_count": {"min": 100, "max": 150},
            "structure": ["Introduction", "Body", "Conclusion"],
            "key_points": ["Use time expressions", "Vary your vocabulary"],
            "sample_phrases": ["First of all", "In addition", "Finally"]
        }
    
    def get_pronunciation_template(self, level: str, focus: str) -> Dict:
        """Get pronunciation template."""
        return {
            "target_sounds": ["/θ/", "/ð/"],
            "words": ["think", "this", "three", "that"],
            "sentences": ["I think this is the third time."],
            "minimal_pairs": [["think", "sink"], ["this", "dis"]],
            "tips": ["Put your tongue between your teeth"]
        }


class DifficultyAdjuster:
    """Adjust content difficulty."""
    
    def adjust_reading(self, text: str, level: str) -> str:
        """Adjust reading difficulty."""
        # In production, this would use NLP to simplify/complexify
        return text


class TopicSelector:
    """Select appropriate topics."""
    
    def select_topic(self, level: str) -> str:
        """Select topic for level."""
        topics = {
            "A1": ["daily_life", "family", "food"],
            "A2": ["hobbies", "travel", "shopping"],
            "B1": ["work", "health", "technology"],
            "B2": ["business", "science", "culture"],
            "C1": ["politics", "philosophy", "literature"],
            "C2": ["abstract_concepts", "specialized_fields"]
        }
        level_topics = topics.get(level, topics["B1"])
        return random.choice(level_topics)
    
    def select_scenario(self, level: str, topic: Optional[str]) -> str:
        """Select conversation scenario."""
        scenarios = [
            "restaurant_ordering",
            "shopping_clothes",
            "asking_directions",
            "job_interview",
            "doctor_appointment"
        ]
        return random.choice(scenarios)
    
    def select_reading_topic(self, level: str) -> str:
        """Select reading topic."""
        return self.select_topic(level)
    
    def select_writing_topic(self, level: str, writing_type: str) -> str:
        """Select writing topic."""
        return self.select_topic(level)
