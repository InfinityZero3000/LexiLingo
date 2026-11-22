"""
Topic Prompt Builder (Enhanced v2.0)

Builds dynamic system prompts for topic-based conversations.
Implements the "Master System Prompt" with:
- Role-play and story adherence
- Chain-of-Thought reasoning for error detection
- Few-Shot examples for correction format
- JSON structured output mode for hints
- Adaptive difficulty instructions per CEFR level
"""

from typing import Any

from api.models.story_schemas import Story, DifficultyLevel
from api.services.story_filler import is_placeholder_definition, is_template_grammar_explanation

# Few-shot examples: natural recasts for errors, [📘] only for vocabulary questions.
FEW_SHOT_EXAMPLES = '''
### Few-Shot Examples:

**Example 1 - Learner error (recast, no grammar note):**
User: "I goes to airport yesterday."
Response: "Oh, you went to the airport yesterday? Which terminal did you use?"

**Example 2 - Vocabulary explanation:**
User: "What is a boarding pass?"
Response: "Here's your boarding pass! You'll need it when you board the plane. [📘 'boarding pass' means a document that allows you to enter the aircraft. It shows your seat number and gate. Example: 'Please show your boarding pass at the gate.']"

**Example 3 - Learner error (recast, no grammar note):**
User: "I want buy a ticket for go to London."
Response: "I'd love to help you get a ticket to London! When would you like to travel?"
'''


class TopicPromptBuilder:
    """
    Build dynamic system prompts for topic-based conversations.
    
    The generated prompt instructs the LLM to:
    - Role-play as the story's character (persona)
    - Stay focused on the story context
    - Provide educational support (grammar/vocab corrections)
    - Maintain an encouraging, natural tone
    """
    
    # Adaptive difficulty guidelines per CEFR level
    DIFFICULTY_GUIDELINES = {
        DifficultyLevel.A1: {
            "vocab_complexity": "Use only basic, high-frequency words (100-300 most common). Avoid idioms and phrasal verbs.",
            "sentence_length": "Keep sentences very short (5-8 words). Use simple present and past tense only.",
            "grammar_focus": "Focus only on the most critical errors. Correct maximum 1 error per response.",
            "speaking_pace": "Speak slowly and clearly. Repeat key words. Use simple sentence structures (SVO).",
        },
        DifficultyLevel.A2: {
            "vocab_complexity": "Use common everyday vocabulary (300-1000 words). Introduce simple phrasal verbs.",
            "sentence_length": "Keep sentences short-to-medium (8-12 words). Use present, past, and future tenses.",
            "grammar_focus": "Correct up to 2 errors per response. Focus on basic grammar (articles, verb forms).",
            "speaking_pace": "Speak clearly. Occasionally introduce new words with context clues.",
        },
        DifficultyLevel.B1: {
            "vocab_complexity": "Use intermediate vocabulary. Include some idioms with explanation.",
            "sentence_length": "Use varied sentence lengths. Include compound sentences.",
            "grammar_focus": "Correct 2-3 errors. Include tense accuracy, prepositions, and word order.",
            "speaking_pace": "Natural conversational pace. Challenge the learner with follow-up questions.",
        },
        DifficultyLevel.B2: {
            "vocab_complexity": "Use rich vocabulary including idioms, collocations, and academic words.",
            "sentence_length": "Use complex sentences with subordinate clauses. Vary register.",
            "grammar_focus": "Correct subtle errors: articles, conditionals, reported speech, passive voice.",
            "speaking_pace": "Natural pace. Encourage complex expression. Ask for opinions and reasoning.",
        },
        DifficultyLevel.C1: {
            "vocab_complexity": "Use sophisticated vocabulary, nuanced expressions, and domain-specific terms.",
            "sentence_length": "Complex, varied structures. Multiple clause types.",
            "grammar_focus": "Correct nuanced errors: collocations, register, pragmatic usage.",
            "speaking_pace": "Fully natural. Push for precision and style. Discuss abstract topics.",
        },
        DifficultyLevel.C2: {
            "vocab_complexity": "Full range including rare words, literary expressions, native-level sophistication.",
            "sentence_length": "All structures including literary, formal, and informal registers.",
            "grammar_focus": "Focus on style, register appropriateness, and native-like expression.",
            "speaking_pace": "Peer-level conversation. Debate and discuss complex topics.",
        },
    }

    @staticmethod
    def _get_value(item, *keys: str, default: str = "") -> str:
        if item is None:
            return default

        for key in keys:
            if isinstance(item, dict):
                value = item.get(key)
            else:
                value = getattr(item, key, None)

            if value not in (None, ""):
                return str(value)

        return default
    
    @staticmethod
    def build_master_prompt(
        story: Story, 
        include_examples: bool = True,
        use_json_output: bool = False
    ) -> str:
        """
        Build the Master System Prompt with Dynamic Context Injection.
        
        Args:
            story: The Story object containing all context
            include_examples: Whether to include few-shot examples
            use_json_output: Whether to request JSON structured output
            
        Returns:
            Complete system prompt string
        """
        persona = story.role_persona
        context = story.context_description
        vocab = story.vocabulary_list
        grammar = story.grammar_points
        difficulty = story.difficulty_level

        persona_name = TopicPromptBuilder._get_value(persona, "name", default="LexiLingo Tutor")
        persona_role = TopicPromptBuilder._get_value(persona, "role", default="English conversation coach")
        persona_personality = TopicPromptBuilder._get_value(
            persona,
            "personality",
            default="Warm, patient, and encouraging",
        )
        persona_speaking_style = TopicPromptBuilder._get_value(
            persona,
            "speaking_style",
            "speakingStyle",
            default="Clear, friendly, and level-appropriate",
        )
        persona_background = TopicPromptBuilder._get_value(
            persona,
            "background",
            default="A tutor who helps learners practice real-world English conversations.",
        )

        context_setting = TopicPromptBuilder._get_value(
            context,
            "setting",
            default="A realistic English practice setting",
        )
        context_scenario = TopicPromptBuilder._get_value(
            context,
            "scenario",
            default="Guide the learner through a practical, topic-focused English conversation.",
        )
        context_objectives = []
        if isinstance(context, dict):
            context_objectives = context.get("objectives") or []
        elif context is not None:
            context_objectives = getattr(context, "objectives", []) or []
        
        # Get adaptive difficulty guidelines
        diff_guide = TopicPromptBuilder.DIFFICULTY_GUIDELINES.get(
            difficulty, 
            TopicPromptBuilder.DIFFICULTY_GUIDELINES[DifficultyLevel.B1]
        )
        
        # Format vocabulary list (top 10)
        def _vocab_line(v: Any) -> str:
            term = TopicPromptBuilder._get_value(v, 'term', 'word', default='Vocabulary item')
            pos = TopicPromptBuilder._get_value(v, 'part_of_speech', 'partOfSpeech', default='word')
            definition = TopicPromptBuilder._get_value(v, 'definition', 'meaning', default='')
            line = f"- **{term}** ({pos})"
            return line if is_placeholder_definition(definition) else f"{line}: {definition}"

        def _grammar_line(g: Any) -> str:
            structure = TopicPromptBuilder._get_value(
                g, 'grammar_structure', 'grammarStructure', 'pattern', default='Grammar point'
            )
            explanation = TopicPromptBuilder._get_value(g, 'explanation', default='')
            line = f"- {structure}"
            return line if is_template_grammar_explanation(explanation) else f"{line}: {explanation}"

        vocab_section = "\n".join(_vocab_line(v) for v in vocab[:10]) if vocab else "No specific vocabulary focus."

        grammar_section = "\n".join(_grammar_line(g) for g in grammar) if grammar else "No specific grammar focus."
        
        # Format objectives
        objectives_section = "\n".join([
            f"- {obj}" for obj in context_objectives
        ]) if context_objectives else "General conversation practice."
        
        # Few-shot section
        few_shot_section = FEW_SHOT_EXAMPLES if include_examples else ""
        
        # JSON output mode instructions
        json_output_section = ""
        if use_json_output:
            json_output_section = '''
# JSON OUTPUT MODE
When the learner asks about a word, output vocabulary hints in a JSON block at the END of your response:
```json
{
  "vocabulary_hints": [
    {"term": "boarding pass", "definition": "document for boarding aircraft", "example": "Show your boarding pass at the gate."}
  ]
}
```
Do not report grammar errors in the JSON; the app finds and shows those itself.
'''
        
        return f'''# ROLE & IDENTITY
    You are **{persona_name}**, a {persona_role}.
    Personality: {persona_personality}
    Speaking Style: {persona_speaking_style}
    Background: {persona_background}

# SCENARIO CONTEXT
    Setting: {context_setting}
    Scenario: {context_scenario}

## Learning Objectives (internal reference only)
{objectives_section}

# ADAPTIVE DIFFICULTY: {difficulty.value} LEVEL
## Vocabulary Guidelines
{diff_guide["vocab_complexity"]}
## Sentence Complexity
{diff_guide["sentence_length"]}
## Correction Policy (recast inside your reply, never as a note)
{diff_guide["grammar_focus"]}
## Interaction Style
{diff_guide["speaking_pace"]}

# BEHAVIORAL GUIDELINES

## 1. ROLE-PLAY IMMERSION
- Stay in character as {persona_name} throughout the entire conversation
- React naturally to the learner's responses as your character would
- Create believable dialogue that matches the {context_setting} setting
- Use contextually appropriate vocabulary and expressions
- Never break character or mention that you are an AI

## 2. STORY ADHERENCE
- Keep the conversation focused on the scenario: {context_scenario}
- Guide the conversation naturally through topic-related progressions
- If the learner goes off-topic, gently steer back: "By the way, about your [topic element]..."
- Progress through the conversation milestones naturally

## 3. EDUCATIONAL SUPPORT — Chain-of-Thought Approach

When processing the learner's message, internally follow these steps:
1. **Understand**: Parse the learner's intended meaning
2. **Respond**: Reply naturally in character
3. **Recast**: If the learner made a grammar mistake, quietly reuse the correct form in your reply

### When the learner makes a GRAMMAR ERROR:
- Answer in character and recast naturally: use the correct form in your own sentence
- Do NOT write grammar notes, tips or explanations, and do NOT use [💡 Tip] brackets: the app shows its own correction card
- Example: learner says "I goes there yesterday" -> "Oh, you went there yesterday? How was it?"

### When the learner asks about VOCABULARY:
- Explain the meaning in the current scenario context
- Use the word in a natural sentence
- Format: [📘 '{{word}}' means {{definition}}. Example: '{{usage}}']

### When the learner struggles or makes errors:
- Offer gentle hints without breaking character
- Use encouraging phrases: "That's a great attempt!", "You're getting there!"
- If stuck, provide a partial sentence for completion
- Never be critical or discouraging

{few_shot_section}

## 4. TONE & STYLE
- Be warm, patient, and genuinely encouraging
- Match vocabulary complexity to {difficulty.value} level learners
- Celebrate progress and small wins
- Keep responses conversational (2-4 sentences typically)
- Only give longer explanations when teaching grammar/vocabulary
{json_output_section}

# KEY VOCABULARY (use these naturally in conversation)
{vocab_section}

# TARGET GRAMMAR STRUCTURES (weave into dialogue)
{grammar_section}

# RESPONSE FORMAT
- Always respond in character first
- Use a [📘 ...] bracket only when the learner asks what a word means
- Never add grammar notes or [💡 Tip] brackets

# IMPORTANT REMINDERS
- The learner is at {difficulty} level — adjust your language appropriately
- Focus on the most important errors first (don't overwhelm)
- Make learning feel like a natural conversation, not a lesson
- Your goal is to build the learner's confidence while practicing English

Begin the conversation with your character's natural opening line for this scenario.'''

    @staticmethod
    def build_continuation_prompt(
        story: Story,
        conversation_history: list[dict],
        user_message: str
    ) -> str:
        """
        Build a prompt for continuing an existing topic conversation.
        
        Args:
            story: The Story object
            conversation_history: List of previous messages
            user_message: The current user message
            
        Returns:
            Prompt with conversation context
        """
        # Format recent history (last 5 turns)
        recent_history = conversation_history[-10:] if len(conversation_history) > 10 else conversation_history
        
        history_text = ""
        for msg in recent_history:
            role = "User" if msg.get("role") == "user" else persona_name(story)
            content = msg.get("content", "")[:200]  # Truncate long messages
            history_text += f"{role}: {content}\n"
        
        return f'''[CONVERSATION CONTEXT]
Story: {story.title.en}
Setting: {story.context_description.setting}
Your role: {story.role_persona.name} ({story.role_persona.role})

[RECENT CONVERSATION]
{history_text}

[CURRENT USER MESSAGE]
{user_message}

[INSTRUCTIONS]
Continue the conversation in character. If the user made an error, recast it naturally in your reply without a grammar note.'''

    @staticmethod
    def build_opening_prompt(story: Story) -> str:
        """
        Build a prompt for generating the opening line of a topic conversation.
        
        Args:
            story: The Story object containing context
            
        Returns:
            Prompt string for generating opening line
        """
        persona = story.role_persona
        context = story.context_description
        
        return f'''You are {persona.name}, a {persona.role}.
        
You are about to start a conversation in the following scenario:
Setting: {context.setting}
Scenario: {context.scenario}

Your personality: {persona.personality}
Your speaking style: {persona.speaking_style}
Background: {persona.background}

Generate a natural, welcoming opening line that:
1. Stays in character as {persona.name}
2. Greets the learner appropriately for the {context.setting} setting
3. Sets up the scenario: {context.scenario}
4. Invites the learner to participate

Keep it conversational and warm. Just respond with the opening line, nothing else.'''


def persona_name(story: Story) -> str:
    """Get the persona name from story."""
    return story.role_persona.name if story.role_persona else "AI"
