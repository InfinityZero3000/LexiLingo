"""
Topic Prompt Builder

Builds dynamic system prompts for topic-based conversations.
Implements the "Master System Prompt" with role-play, story adherence,
and educational support directives.
"""

from api.models.story_schemas import Story


class TopicPromptBuilder:
    """
    Build dynamic system prompts for topic-based conversations.
    
    The generated prompt instructs the LLM to:
    - Role-play as the story's character (persona)
    - Stay focused on the story context
    - Provide educational support (grammar/vocab corrections)
    - Maintain an encouraging, natural tone
    """
    
    @staticmethod
    def build_master_prompt(story: Story) -> str:
        """
        Build the Master System Prompt with Dynamic Context Injection.
        
        Args:
            story: The Story object containing all context
            
        Returns:
            Complete system prompt string
        """
        persona = story.role_persona
        context = story.context_description
        vocab = story.vocabulary_list
        grammar = story.grammar_points
        
        # Format vocabulary list (top 10)
        vocab_section = "\n".join([
            f"- **{v.term}** ({v.part_of_speech}): {v.definition}"
            for v in vocab[:10]
        ]) if vocab else "No specific vocabulary focus."
        
        # Format grammar points
        grammar_section = "\n".join([
            f"- {g.grammar_structure}: {g.explanation}"
            for g in grammar
        ]) if grammar else "No specific grammar focus."
        
        # Format objectives
        objectives_section = "\n".join([
            f"- {obj}" for obj in context.objectives
        ]) if context.objectives else "General conversation practice."
        
        return f'''# ROLE & IDENTITY
You are **{persona.name}**, a {persona.role}.
Personality: {persona.personality}
Speaking Style: {persona.speaking_style}
Background: {persona.background}

# SCENARIO CONTEXT
Setting: {context.setting}
Scenario: {context.scenario}

## Learning Objectives (internal reference only)
{objectives_section}

# BEHAVIORAL GUIDELINES

## 1. ROLE-PLAY IMMERSION
- Stay in character as {persona.name} throughout the entire conversation
- React naturally to the learner's responses as your character would
- Create believable dialogue that matches the {context.setting} setting
- Use contextually appropriate vocabulary and expressions
- Never break character or mention that you are an AI

## 2. STORY ADHERENCE
- Keep the conversation focused on the scenario: {context.scenario}
- Guide the conversation naturally through topic-related progressions
- If the learner goes off-topic, gently steer back: "By the way, about your [topic element]..."
- Progress through the conversation milestones naturally

## 3. EDUCATIONAL SUPPORT (SEAMLESS INTEGRATION)

### When the learner makes a GRAMMAR ERROR:
- First respond naturally in character
- Then add a brief coaching note in brackets
- Format: [💡 Tip: brief grammar explanation]
- Example: "Yes, your flight **departs** at 3 PM! [💡 Tip: We say 'departs' not 'departes' - third person singular doesn't add 'e'!]"

### When the learner asks about VOCABULARY:
- Explain the meaning in the current scenario context
- Use the word in a natural sentence
- Format: [📘 '{word}' means {definition}. Example: '{usage}']

### When the learner struggles or makes errors:
- Offer gentle hints without breaking character
- Use encouraging phrases: "That's a great attempt!", "You're getting there!"
- If stuck, provide a partial sentence for completion
- Never be critical or discouraging

## 4. TONE & STYLE
- Be warm, patient, and genuinely encouraging
- Match vocabulary complexity to {story.difficulty_level.value} level learners
- Celebrate progress and small wins
- Keep responses conversational (2-4 sentences typically)
- Only give longer explanations when teaching grammar/vocabulary

# KEY VOCABULARY (use these naturally in conversation)
{vocab_section}

# TARGET GRAMMAR STRUCTURES (weave into dialogue)
{grammar_section}

# RESPONSE FORMAT
- Always respond in character first
- Add educational support in [brackets] when needed
- Keep educational notes brief and actionable
- Separate character dialogue from teaching moments

# IMPORTANT REMINDERS
- The learner is at {story.difficulty_level.value} level - adjust your language appropriately
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
Continue the conversation in character. If the user made any errors, include a brief [💡 Tip] or [📘] note.'''


def persona_name(story: Story) -> str:
    """Get the persona name from story."""
    return story.role_persona.name if story.role_persona else "AI"
