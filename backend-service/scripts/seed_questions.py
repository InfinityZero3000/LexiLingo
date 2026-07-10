"""
Seed Question Bank
==================
Seeds MCQ questions linked to grammar items, then assigns question_ids to
test exams. Fully idempotent: clears question_bank first, re-creates all
questions, then re-links test_exams.question_ids.

Run:
    cd backend-service
    venv/bin/python3 -m scripts.seed_questions
"""

import sys, os
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

import asyncio
import random
from sqlalchemy import select, delete, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import AsyncSessionLocal
from app.models.content import GrammarItem, QuestionItem, TestExam


# ─────────────────────────────────────────────────────────────────────────────
# MCQ data keyed by grammar item title.
# Each entry: list of {prompt, options, answer, explanation}
# options = [A, B, C, D];  answer = correct option string
# ─────────────────────────────────────────────────────────────────────────────

GRAMMAR_QUESTIONS: dict[str, list[dict]] = {

    # ═════════════════════════ A1 ═════════════════════════════════════════════

    "Articles: A, An, The": [
        {
            "prompt": "Choose the correct article: '___ apple a day keeps the doctor away.'",
            "options": ["A", "An", "The", "—"],
            "answer": "An",
            "explanation": "Use 'an' before words that start with a vowel sound. 'Apple' starts with the vowel /æ/.",
        },
        {
            "prompt": "Which sentence uses the article correctly?",
            "options": [
                "She is a honest person.",
                "He went to the school yesterday.",
                "I need a pen, please.",
                "She bought the car last week for a first time.",
            ],
            "answer": "I need a pen, please.",
            "explanation": "'A pen' = an unspecific, singular countable noun. The other options misuse articles.",
        },
        {
            "prompt": "Fill in the blank: 'Can you close ___ door, please?'",
            "options": ["a", "an", "the", "—"],
            "answer": "the",
            "explanation": "Use 'the' when it is clear which specific thing you mean — both speaker and listener know which door.",
        },
        {
            "prompt": "Which noun phrase does NOT need an article in English?",
            "options": ["___ ocean", "___ book on the table", "___ love (in general)", "___ cat next door"],
            "answer": "___ love (in general)",
            "explanation": "Abstract nouns used in a general sense (love, peace, music) take no article.",
        },
    ],

    "The Verb 'To Be': Am / Is / Are": [
        {
            "prompt": "Choose the correct form: 'My parents ___ doctors.'",
            "options": ["am", "is", "are", "be"],
            "answer": "are",
            "explanation": "'My parents' is third-person plural, so the correct form is 'are'.",
        },
        {
            "prompt": "Which sentence is correct?",
            "options": [
                "She am very happy today.",
                "They is my best friends.",
                "I are a student.",
                "He is tall and friendly.",
            ],
            "answer": "He is tall and friendly.",
            "explanation": "'He' is third-person singular, requiring 'is'. All other options use the wrong form of 'to be'.",
        },
        {
            "prompt": "What is the negative form of 'I am late'?",
            "options": ["I am not late.", "I are not late.", "I be not late.", "I is not late."],
            "answer": "I am not late.",
            "explanation": "Negation of 'am' is 'am not' (or contraction 'I'm not').",
        },
        {
            "prompt": "Choose the correct question form: '___ she a teacher?'",
            "options": ["Am", "Is", "Are", "Be"],
            "answer": "Is",
            "explanation": "For third-person singular (she/he/it), use 'Is' in questions.",
        },
    ],

    "Simple Present Tense": [
        {
            "prompt": "Choose the correct verb form: 'She ___ to school every day.'",
            "options": ["go", "goes", "going", "gone"],
            "answer": "goes",
            "explanation": "Third-person singular (she/he/it) adds -s/-es to the base verb in simple present.",
        },
        {
            "prompt": "Which sentence uses simple present correctly?",
            "options": [
                "He don't like coffee.",
                "They doesn't play football.",
                "The sun rises in the east.",
                "We eats lunch at noon.",
            ],
            "answer": "The sun rises in the east.",
            "explanation": "This is a permanent truth. 'Rises' is correct for third-person singular.",
        },
        {
            "prompt": "What is the correct negative: 'I ___ speak French.'",
            "options": ["doesn't", "don't", "not", "isn't"],
            "answer": "don't",
            "explanation": "Use 'don't' (do not) with I/you/we/they for negation in simple present.",
        },
        {
            "prompt": "How do you form the question: 'You work here.' → Question:",
            "options": [
                "Work you here?",
                "Do you work here?",
                "Does you work here?",
                "Are you work here?",
            ],
            "answer": "Do you work here?",
            "explanation": "Use auxiliary 'do' + subject + base verb for yes/no questions with I/you/we/they.",
        },
    ],

    "Subject Pronouns vs Object Pronouns": [
        {
            "prompt": "Choose the correct pronoun: 'The teacher gave ___ the homework.'",
            "options": ["I", "we", "us", "they"],
            "answer": "us",
            "explanation": "'Us' is an object pronoun (receives the action). 'I/we' are subject pronouns.",
        },
        {
            "prompt": "Which sentence is correct?",
            "options": [
                "Me and him went to the park.",
                "She and I went to the park.",
                "Her and me went to the park.",
                "Him and me went to the park.",
            ],
            "answer": "She and I went to the park.",
            "explanation": "Subject pronouns (she, I) are used as the subject of the sentence.",
        },
        {
            "prompt": "Choose the object pronoun: 'Can you help ___?' (referring to Tom and Anna)",
            "options": ["they", "we", "their", "them"],
            "answer": "them",
            "explanation": "'Them' is the object pronoun for third-person plural (they).",
        },
    ],

    "There is / There are": [
        {
            "prompt": "Choose correctly: '___ a book on the table.'",
            "options": ["There are", "There is", "It is", "They are"],
            "answer": "There is",
            "explanation": "Use 'there is' with singular or uncountable nouns.",
        },
        {
            "prompt": "Choose correctly: '___ many students in the library.'",
            "options": ["There is", "There are", "It are", "They is"],
            "answer": "There are",
            "explanation": "Use 'there are' with plural countable nouns.",
        },
        {
            "prompt": "What is the question form of 'There is a problem'?",
            "options": [
                "There is a problem?",
                "Is there a problem?",
                "Are there a problem?",
                "Does there is a problem?",
            ],
            "answer": "Is there a problem?",
            "explanation": "Invert 'is' and 'there' to form a yes/no question: 'Is there...?'",
        },
    ],

    # ═════════════════════════ A2 ═════════════════════════════════════════════

    "Comparative Adjectives": [
        {
            "prompt": "Choose the correct comparative: 'This coffee is ___ than that one.'",
            "options": ["hot", "hotter", "more hot", "hottest"],
            "answer": "hotter",
            "explanation": "Short adjectives (1-2 syllables) add -er/-r for comparatives: hot → hotter.",
        },
        {
            "prompt": "Which is correct for 'interesting'?",
            "options": [
                "This film is more interestinger.",
                "This film is interestinger than the book.",
                "This film is more interesting than the book.",
                "This film is most interesting.",
            ],
            "answer": "This film is more interesting than the book.",
            "explanation": "Long adjectives (3+ syllables) use 'more' for comparatives.",
        },
        {
            "prompt": "Fill in: 'She runs ___ than her brother.'",
            "options": ["more fast", "fastest", "more faster", "faster"],
            "answer": "faster",
            "explanation": "'Fast' is a one-syllable adjective: comparative = faster (no 'more').",
        },
    ],

    "Comparative and Superlative Adjectives": [
        {
            "prompt": "Choose the correct superlative: 'Mount Everest is ___ mountain in the world.'",
            "options": ["higher", "the higher", "the highest", "more high"],
            "answer": "the highest",
            "explanation": "Superlatives use 'the + adjective + -est' for short adjectives.",
        },
        {
            "prompt": "Which sentence is correct?",
            "options": [
                "She is the most beautifulest girl.",
                "He is the tallest player on the team.",
                "This is more worst than before.",
                "They are the more experienced.",
            ],
            "answer": "He is the tallest player on the team.",
            "explanation": "'Tallest' is the correct superlative of 'tall' (one-syllable adjective).",
        },
        {
            "prompt": "What is the comparative and superlative of 'good'?",
            "options": [
                "gooder / goodest",
                "more good / most good",
                "better / best",
                "well / best",
            ],
            "answer": "better / best",
            "explanation": "'Good' is an irregular adjective: good → better → best.",
        },
    ],

    "Countable and Uncountable Nouns": [
        {
            "prompt": "Which of these is an uncountable noun?",
            "options": ["chair", "water", "apple", "book"],
            "answer": "water",
            "explanation": "Uncountable nouns refer to substances or concepts that can't be individually counted: water, air, music.",
        },
        {
            "prompt": "Which sentence is correct?",
            "options": [
                "Can I have an information?",
                "She gave me many advices.",
                "I need some help, please.",
                "They found two furnitures.",
            ],
            "answer": "I need some help, please.",
            "explanation": "'Help' is uncountable. Use 'some' (not 'a' or plural) with uncountable nouns.",
        },
        {
            "prompt": "How do you make 'water' countable?",
            "options": [
                "Two waters, please.",
                "Two glass of water.",
                "Two glasses of water.",
                "Two water glasses.",
            ],
            "answer": "Two glasses of water.",
            "explanation": "Use a 'unit of measurement + of' structure: two glasses of water, three cups of coffee.",
        },
    ],

    "Possessive Adjectives and Possessive Pronouns": [
        {
            "prompt": "Choose the correct word: 'Is this ___ bag?' (asking a woman)",
            "options": ["hers", "her", "his", "their"],
            "answer": "her",
            "explanation": "'Her' is a possessive adjective (modifies a noun: her bag). 'Hers' is a possessive pronoun (used alone).",
        },
        {
            "prompt": "Choose the possessive pronoun: 'That car is ___.' (belonging to us)",
            "options": ["our", "ours", "us", "we"],
            "answer": "ours",
            "explanation": "Possessive pronouns (mine, yours, his, hers, ours, theirs) stand alone — no noun follows.",
        },
        {
            "prompt": "Which sentence is correct?",
            "options": [
                "The dog ate it's food.",
                "This is my book and that is your.",
                "Whose pen is this? It's mine.",
                "The house and it's garden are beautiful.",
            ],
            "answer": "Whose pen is this? It's mine.",
            "explanation": "'Mine' is a possessive pronoun. Note: 'its' (possessive adjective) has no apostrophe; 'it's' = 'it is'.",
        },
    ],

    "Simple Past Tense": [
        {
            "prompt": "Choose the correct form: 'She ___ a letter yesterday.'",
            "options": ["write", "writes", "wrote", "written"],
            "answer": "wrote",
            "explanation": "'Write' is an irregular verb: write → wrote → written. Simple past = wrote.",
        },
        {
            "prompt": "Which sentence uses simple past correctly?",
            "options": [
                "I goed to the cinema last night.",
                "They didn't went home early.",
                "He didn't study for the exam.",
                "Did she cried?",
            ],
            "answer": "He didn't study for the exam.",
            "explanation": "Negation: 'didn't + base verb'. 'Study' stays in base form after 'didn't'.",
        },
        {
            "prompt": "What is the question form of 'You called me'?",
            "options": [
                "Called you me?",
                "Did you called me?",
                "Did you call me?",
                "Have you call me?",
            ],
            "answer": "Did you call me?",
            "explanation": "Yes/no questions in simple past: 'Did + subject + base verb?'",
        },
        {
            "prompt": "Which verb is irregular in the past?",
            "options": ["walk → walked", "jump → jumped", "go → goed", "buy → bought"],
            "answer": "buy → bought",
            "explanation": "'Buy' is irregular: buy → bought. The others are regular except 'go → went' (not 'goed').",
        },
    ],

    "There Is / There Are": [
        {
            "prompt": "Choose the correct form: '___ a lot of noise outside.'",
            "options": ["There are", "There is", "There were", "They are"],
            "answer": "There is",
            "explanation": "'Noise' is uncountable, so use 'there is'.",
        },
        {
            "prompt": "Negative form of 'There are some cookies' →",
            "options": [
                "There aren't some cookies.",
                "There isn't any cookies.",
                "There aren't any cookies.",
                "There are no some cookies.",
            ],
            "answer": "There aren't any cookies.",
            "explanation": "Use 'some' in positives; use 'any' in negatives and questions with countable nouns.",
        },
        {
            "prompt": "Choose the past form: 'When I was a child, ___ a park near my house.'",
            "options": ["there is", "there are", "there was", "there were"],
            "answer": "there was",
            "explanation": "Past tense of 'there is' = 'there was' (singular); 'there are' → 'there were' (plural).",
        },
    ],

    # ═════════════════════════ B1 ═════════════════════════════════════════════

    "Present Perfect Tense": [
        {
            "prompt": "Choose correctly: 'I ___ to Japan three times.'",
            "options": ["went", "have been", "go", "was"],
            "answer": "have been",
            "explanation": "Use present perfect for experiences without a specific time. 'Have been' = have visited.",
        },
        {
            "prompt": "Which sentence uses present perfect correctly?",
            "options": [
                "She has finished her homework yesterday.",
                "I have seen that film last week.",
                "Have you ever tasted sushi?",
                "They have went to school this morning.",
            ],
            "answer": "Have you ever tasted sushi?",
            "explanation": "Present perfect with 'ever' asks about life experience. Don't use with specific past times (yesterday, last week).",
        },
        {
            "prompt": "Choose the correct form: 'She ___ in London for five years.'",
            "options": ["lived", "has lived", "is living", "live"],
            "answer": "has lived",
            "explanation": "Use present perfect with 'for' when the action started in the past and continues now.",
        },
        {
            "prompt": "What does 'just' signal in present perfect?",
            "options": [
                "The action happened at a specific time in the past.",
                "The action began in the past and is still ongoing.",
                "The action was completed very recently.",
                "The action will happen soon.",
            ],
            "answer": "The action was completed very recently.",
            "explanation": "'Just' in present perfect signals very recent completion: 'I've just eaten.' = I ate a moment ago.",
        },
    ],

    "Modal Verbs: Should, Must, Have To": [
        {
            "prompt": "Choose the correct modal: 'You ___ wear a seatbelt. It's the law.'",
            "options": ["should", "must", "can", "might"],
            "answer": "must",
            "explanation": "'Must' expresses strong obligation or necessity (from the speaker's authority or a rule).",
        },
        {
            "prompt": "Which sentence gives advice (not obligation)?",
            "options": [
                "You must stop at a red light.",
                "You should get more sleep.",
                "You have to pay a fine.",
                "You must not smoke here.",
            ],
            "answer": "You should get more sleep.",
            "explanation": "'Should' gives recommendations or advice. 'Must/have to' express obligation.",
        },
        {
            "prompt": "What is the difference between 'must not' and 'don't have to'?",
            "options": [
                "They mean the same thing.",
                "'Must not' = prohibited; 'don't have to' = not necessary (but allowed).",
                "'Must not' = advice; 'don't have to' = prohibition.",
                "'Don't have to' is more formal than 'must not'.",
            ],
            "answer": "'Must not' = prohibited; 'don't have to' = not necessary (but allowed).",
            "explanation": "'You mustn't park here' = parking is forbidden. 'You don't have to come' = it's optional, not required.",
        },
    ],

    "Modal Verbs — Ability, Permission, Obligation": [
        {
            "prompt": "Choose the correct modal for ability: 'She ___ speak three languages.'",
            "options": ["must", "should", "can", "shall"],
            "answer": "can",
            "explanation": "'Can' expresses present ability (skill or capability).",
        },
        {
            "prompt": "Which modal asks for permission politely?",
            "options": [
                "I must borrow your pen.",
                "I will borrow your pen.",
                "May I borrow your pen?",
                "I can borrow your pen.",
            ],
            "answer": "May I borrow your pen?",
            "explanation": "'May I...?' is a polite way to ask for permission. 'Can I...?' is more informal.",
        },
        {
            "prompt": "Past form of 'can' for ability is ___.",
            "options": ["could", "may", "should", "must"],
            "answer": "could",
            "explanation": "'Could' is the past tense of 'can' and is used for past ability: 'I could swim when I was five.'",
        },
    ],

    "Gerunds and Infinitives": [
        {
            "prompt": "Which verb must be followed by a GERUND (verb + -ing)?",
            "options": ["want", "decide", "enjoy", "plan"],
            "answer": "enjoy",
            "explanation": "'Enjoy' always takes a gerund: 'enjoy swimming'. Compare: want/decide/plan + infinitive.",
        },
        {
            "prompt": "Choose correctly: 'She stopped ___ to answer the phone.'",
            "options": ["to work", "work", "working", "worked"],
            "answer": "working",
            "explanation": "'Stop + gerund' = cease an activity. ('Stop + infinitive' = stop in order to do something.)",
        },
        {
            "prompt": "Which sentence is grammatically correct?",
            "options": [
                "I want going to the beach.",
                "He avoids to drive at night.",
                "We decided to leave early.",
                "They suggested to take a bus.",
            ],
            "answer": "We decided to leave early.",
            "explanation": "'Decide' takes an infinitive (to + verb). 'Avoid/suggest' take gerunds.",
        },
    ],

    "Present & Past Passive Voice": [
        {
            "prompt": "Convert to passive: 'The chef cooks the meal.'",
            "options": [
                "The meal is cooked by the chef.",
                "The meal was cooked by the chef.",
                "The meal cooked by the chef.",
                "The meal is cooking by the chef.",
            ],
            "answer": "The meal is cooked by the chef.",
            "explanation": "Present passive = is/are + past participle. 'Cook' → 'cooked'.",
        },
        {
            "prompt": "Choose the correct past passive: 'The window ___ by the storm.'",
            "options": ["was break", "is broken", "was broken", "were broken"],
            "answer": "was broken",
            "explanation": "Past passive = was/were + past participle. 'Window' is singular → 'was broken'.",
        },
        {
            "prompt": "When do we use passive voice?",
            "options": [
                "When the agent (doer) is unknown, obvious, or unimportant.",
                "Always, to sound more formal.",
                "Only in written English.",
                "When the subject and object are the same person.",
            ],
            "answer": "When the agent (doer) is unknown, obvious, or unimportant.",
            "explanation": "E.g. 'The building was destroyed.' – we don't know or care who destroyed it.",
        },
    ],

    "Conditional Sentences: 1st & 2nd": [
        {
            "prompt": "Choose the 1st conditional: 'If it ___, we ___ inside.'",
            "options": [
                "rains / stay",
                "rains / will stay",
                "will rain / stay",
                "rained / would stay",
            ],
            "answer": "rains / will stay",
            "explanation": "1st conditional: If + simple present → will + base verb. For real/possible future situations.",
        },
        {
            "prompt": "Which is a 2nd conditional sentence?",
            "options": [
                "If I study, I will pass.",
                "If I studied more, I would pass.",
                "If I had studied, I would have passed.",
                "If I study, I pass.",
            ],
            "answer": "If I studied more, I would pass.",
            "explanation": "2nd conditional: If + simple past → would + base verb. For hypothetical/unlikely present/future situations.",
        },
        {
            "prompt": "What does the 2nd conditional express?",
            "options": [
                "A real and likely future event.",
                "A past regret.",
                "A hypothetical or unreal present/future situation.",
                "A habitual action in the present.",
            ],
            "answer": "A hypothetical or unreal present/future situation.",
            "explanation": "E.g. 'If I were rich, I would travel the world.' is imaginary — the speaker is not rich.",
        },
    ],

    "Conditionals: Zero and First": [
        {
            "prompt": "Which is a zero conditional?",
            "options": [
                "If you heat water to 100°C, it boils.",
                "If it rains, I will stay home.",
                "If I were you, I would apologise.",
                "If she had called, I would have answered.",
            ],
            "answer": "If you heat water to 100°C, it boils.",
            "explanation": "Zero conditional: If + simple present, simple present. Used for scientific facts and general truths.",
        },
        {
            "prompt": "First conditional uses ___ tense in the if-clause.",
            "options": ["simple future", "simple past", "simple present", "past perfect"],
            "answer": "simple present",
            "explanation": "First conditional structure: If + simple present, will + base verb.",
        },
        {
            "prompt": "Choose the first conditional: 'If you ___ hard, you ___ the exam.'",
            "options": [
                "worked / would pass",
                "work / will pass",
                "will work / pass",
                "worked / will pass",
            ],
            "answer": "work / will pass",
            "explanation": "First conditional: if + present simple → will + infinitive.",
        },
    ],

    "Reported Speech — Statements": [
        {
            "prompt": "Report: 'I am tired,' he said.",
            "options": [
                "He said that he is tired.",
                "He said that he was tired.",
                "He said that I am tired.",
                "He told he was tired.",
            ],
            "answer": "He said that he was tired.",
            "explanation": "Tense shifts back in reported speech: am → was. Use 'he' (not 'I') for the subject.",
        },
        {
            "prompt": "Report: 'We will come tomorrow,' they said.",
            "options": [
                "They said they will come the next day.",
                "They said they would come the next day.",
                "They told that they would come tomorrow.",
                "They said they come the following day.",
            ],
            "answer": "They said they would come the next day.",
            "explanation": "'Will' shifts to 'would' in reported speech; 'tomorrow' → 'the next day'.",
        },
        {
            "prompt": "What is the difference between 'said' and 'told' in reported speech?",
            "options": [
                "'Said' requires an object; 'told' does not.",
                "'Told' requires a person object; 'said' does not.",
                "They are completely interchangeable.",
                "'Said' is used for past, 'told' for present.",
            ],
            "answer": "'Told' requires a person object; 'said' does not.",
            "explanation": "'She said (that)...' — no object. 'She told me (that)...' — must have a person object.",
        },
    ],

    "Used to / Would — Past Habits": [
        {
            "prompt": "Choose correctly: 'We ___ live in Paris when I was a child.'",
            "options": ["use to", "used to", "would", "were used to"],
            "answer": "used to",
            "explanation": "'Used to + base verb' describes past states or habits that no longer exist.",
        },
        {
            "prompt": "Which sentence uses 'would' for a past habit correctly?",
            "options": [
                "I would be shy as a child.",
                "She would live near the park.",
                "Every summer, we would visit our grandparents.",
                "He would have a red car.",
            ],
            "answer": "Every summer, we would visit our grandparents.",
            "explanation": "'Would' for past habits works with repeated actions — NOT with stative verbs (be, have, live, know).",
        },
        {
            "prompt": "Which is NOT correct?",
            "options": [
                "I used to love chocolate.",
                "Did you use to play violin?",
                "She didn't use to study much.",
                "They used to visited us often.",
            ],
            "answer": "They used to visited us often.",
            "explanation": "After 'used to', always use the base form of the verb, not past tense.",
        },
    ],

    # ═════════════════════════ B2 ═════════════════════════════════════════════

    "Passive Voice": [
        {
            "prompt": "Choose the correct future passive: 'The results ___ tomorrow.'",
            "options": [
                "will announce",
                "will be announced",
                "are announced",
                "are being announced",
            ],
            "answer": "will be announced",
            "explanation": "Future passive = will be + past participle.",
        },
        {
            "prompt": "Which is a present perfect passive?",
            "options": [
                "The report is written.",
                "The report was written.",
                "The report has been written.",
                "The report will be written.",
            ],
            "answer": "The report has been written.",
            "explanation": "Present perfect passive = has/have been + past participle.",
        },
        {
            "prompt": "When is 'by' used in passive structures?",
            "options": [
                "Always, to complete the passive structure.",
                "Only with animate (living) agents.",
                "Only when the agent is important or informative.",
                "Never — 'by' is not used in passives.",
            ],
            "answer": "Only when the agent is important or informative.",
            "explanation": "We omit 'by + agent' when it is obvious, unknown, or unimportant. We include it when it adds meaningful information.",
        },
    ],

    "Relative Clauses: Defining & Non-Defining": [
        {
            "prompt": "Which sentence contains a NON-DEFINING relative clause?",
            "options": [
                "The book that I read was fascinating.",
                "The woman who lives next door is a doctor.",
                "My sister, who lives in Paris, is visiting next month.",
                "The man that called is waiting outside.",
            ],
            "answer": "My sister, who lives in Paris, is visiting next month.",
            "explanation": "Non-defining relative clauses add extra (non-essential) information and are separated by commas.",
        },
        {
            "prompt": "In a defining relative clause, which relative pronoun can be OMITTED?",
            "options": ["who (subject)", "which (subject)", "that (object)", "whose"],
            "answer": "that (object)",
            "explanation": "Object relative pronouns (who/that/which referring to objects) can be omitted in defining clauses.",
        },
        {
            "prompt": "Choose the correct sentence:",
            "options": [
                "The car, that I bought, is red.",
                "The teacher who taught us retired last year.",
                "My brother, which is a chef, lives in London.",
                "The film which I watched it was boring.",
            ],
            "answer": "The teacher who taught us retired last year.",
            "explanation": "'Who' for people in defining clauses. Non-defining clauses use commas. Don't use 'that' in non-defining clauses.",
        },
    ],

    "Second and Third Conditional": [
        {
            "prompt": "Choose the 3rd conditional: 'If she ___ harder, she ___ the exam.'",
            "options": [
                "had studied / would have passed",
                "studied / would pass",
                "had studied / would pass",
                "studied / would have passed",
            ],
            "answer": "had studied / would have passed",
            "explanation": "3rd conditional: If + past perfect, would have + past participle. Expresses past regret.",
        },
        {
            "prompt": "What does the 3rd conditional express?",
            "options": [
                "A real possibility in the future.",
                "A habitual action in the past.",
                "An imaginary past situation and its imaginary result.",
                "A general truth or natural law.",
            ],
            "answer": "An imaginary past situation and its imaginary result.",
            "explanation": "3rd conditional reflects on the past: 'If I had known, I would have acted differently.'",
        },
        {
            "prompt": "Identify the mixed conditional: 'If I had slept better, I wouldn't be so tired now.'",
            "options": [
                "1st conditional",
                "2nd conditional",
                "3rd conditional",
                "Mixed conditional (3rd → 2nd)",
            ],
            "answer": "Mixed conditional (3rd → 2nd)",
            "explanation": "Mixed conditionals mix time frames: past condition (3rd: had slept) + present result (2nd: would be).",
        },
    ],

    "Third Conditional": [
        {
            "prompt": "Which is correctly formed as a 3rd conditional?",
            "options": [
                "If I would have known, I would tell you.",
                "If I had known, I would have told you.",
                "If I knew, I would have told you.",
                "If I have known, I would tell you.",
            ],
            "answer": "If I had known, I would have told you.",
            "explanation": "3rd conditional: If + past perfect (had known) → would have + past participle (told).",
        },
        {
            "prompt": "What time frame does the third conditional describe?",
            "options": ["Present", "Future", "Past (impossible/unreal)", "Habitual past"],
            "answer": "Past (impossible/unreal)",
            "explanation": "The 3rd conditional imagines a different past: something that didn't happen and its hypothetical result.",
        },
        {
            "prompt": "Fill in: 'If the weather ___ better, we ___ to the beach.'",
            "options": [
                "was / would go",
                "had been / would have gone",
                "would be / had gone",
                "had been / would go",
            ],
            "answer": "had been / would have gone",
            "explanation": "3rd conditional: If + past perfect → would have + past participle.",
        },
    ],

    "Expressing Contrast: Although, Despite, However": [
        {
            "prompt": "Choose the correct connector: '___ the rain, they continued playing.'",
            "options": ["Although", "However", "Despite", "Even though"],
            "answer": "Despite",
            "explanation": "'Despite/in spite of' is followed by a noun or gerund phrase, not a clause.",
        },
        {
            "prompt": "Which sentence is correct?",
            "options": [
                "Despite she was tired, she kept smiling.",
                "Although she was tired, she kept smiling.",
                "However she was tired, she kept smiling.",
                "Despite of the noise, I couldn't concentrate.",
            ],
            "answer": "Although she was tired, she kept smiling.",
            "explanation": "'Although/even though' is followed by a subject + verb clause. 'Despite' takes a noun/gerund.",
        },
        {
            "prompt": "'However' is used to contrast two ___.",
            "options": [
                "Words in the same sentence.",
                "Parts of the same clause.",
                "Separate sentences or independent clauses.",
                "Noun phrases only.",
            ],
            "answer": "Separate sentences or independent clauses.",
            "explanation": "'However' is an adverb used to contrast two separate ideas/sentences: 'He tried. However, he failed.'",
        },
    ],

    "The Subjunctive Mood": [
        {
            "prompt": "Choose the correct subjunctive form: 'She recommended that he ___ a doctor.'",
            "options": ["see", "sees", "would see", "saw"],
            "answer": "see",
            "explanation": "The 'mandative subjunctive' (suggest/recommend/insist + that) uses the base verb regardless of subject.",
        },
        {
            "prompt": "Which sentence uses the subjunctive correctly?",
            "options": [
                "I wish I was taller.",
                "If I were you, I would apologise.",
                "She suggested that he goes home.",
                "They insisted he leaves immediately.",
            ],
            "answer": "If I were you, I would apologise.",
            "explanation": "In formal/careful English, the past subjunctive uses 'were' for all persons (not 'was') in unreal conditionals.",
        },
        {
            "prompt": "The phrase 'as it were' is an example of the ___ subjunctive.",
            "options": ["mandative", "formulaic", "conditional", "nominal"],
            "answer": "formulaic",
            "explanation": "Formulaic subjunctives are fixed phrases: 'as it were', 'be that as it may', 'far be it from me'.",
        },
    ],

    # ═════════════════════════ C1 ═════════════════════════════════════════════

    "Advanced Modals: Speculation & Deduction": [
        {
            "prompt": "Choose the correct modal for a deduction about the past: 'She ___ left already — the lights are off.'",
            "options": [
                "must leave",
                "must have left",
                "should leave",
                "might leave",
            ],
            "answer": "must have left",
            "explanation": "'Must have + past participle' = near-certain deduction about a past event.",
        },
        {
            "prompt": "Which expresses LOW probability about a present situation?",
            "options": [
                "He must be home by now.",
                "She should be sleeping.",
                "They can't be serious.",
                "It might be him at the door.",
            ],
            "answer": "It might be him at the door.",
            "explanation": "'Might/could' express low to medium probability. 'Must' = near certain; 'can't' = near impossible.",
        },
        {
            "prompt": "'You can't have finished the exam so quickly!' expresses:",
            "options": [
                "A prohibition in the past.",
                "An inability in the past.",
                "A near-certain negative deduction about the past.",
                "A regret about the past.",
            ],
            "answer": "A near-certain negative deduction about the past.",
            "explanation": "'Can't have + past participle' expresses strong disbelief or near-impossible deduction about the past.",
        },
    ],

    "Inversion for Emphasis": [
        {
            "prompt": "Identify the inverted sentence:",
            "options": [
                "Never I have seen such a beautiful sunset.",
                "Never have I seen such a beautiful sunset.",
                "I have never seen such a beautiful sunset.",
                "Such a beautiful sunset I never have seen.",
            ],
            "answer": "Never have I seen such a beautiful sunset.",
            "explanation": "Fronting a negative adverb (never, rarely, seldom) triggers subject-auxiliary inversion.",
        },
        {
            "prompt": "Which adverbial triggers inversion?",
            "options": ["Always", "Sometimes", "Hardly ever", "Often"],
            "answer": "Hardly ever",
            "explanation": "Negative/restrictive adverbs (hardly, never, rarely, seldom, little, not only) trigger inversion when fronted.",
        },
        {
            "prompt": "Complete: 'Not only ___ late, but he also forgot his report.'",
            "options": [
                "he was",
                "was he",
                "he is",
                "is he",
            ],
            "answer": "was he",
            "explanation": "After 'not only' fronted at the start of a clause, invert the subject and auxiliary: 'Not only was he late...'",
        },
    ],

    "Cleft Sentences for Focus and Emphasis": [
        {
            "prompt": "Which is a correct 'it-cleft' sentence?",
            "options": [
                "It is John who she loves.",
                "It was John who loved she.",
                "It's that John she loves.",
                "John it is who she loves.",
            ],
            "answer": "It is John who she loves.",
            "explanation": "It-cleft structure: It is/was + [focus element] + that/who + rest of sentence.",
        },
        {
            "prompt": "Change to a wh-cleft: 'I really need a holiday.'",
            "options": [
                "What I really need is a holiday.",
                "It is a holiday that I really need.",
                "A holiday is what I really need to.",
                "What is it I really need a holiday.",
            ],
            "answer": "What I really need is a holiday.",
            "explanation": "Wh-cleft (pseudo-cleft) structure: What + subject + verb + is/was + [focus element].",
        },
        {
            "prompt": "Cleft sentences are used to:",
            "options": [
                "Make sentences shorter and simpler.",
                "Highlight and emphasise a particular piece of information.",
                "Connect two independent clauses with contrast.",
                "Change active voice to passive voice.",
            ],
            "answer": "Highlight and emphasise a particular piece of information.",
            "explanation": "Cleft sentences split one clause into two to bring focus to a specific element.",
        },
    ],

    "Ellipsis and Substitution": [
        {
            "prompt": "Identify the ellipsis: 'A: Can you drive? B: Yes, I can.'",
            "options": [
                "No ellipsis present.",
                "The word 'Yes' is ellipsis.",
                "'Drive' is omitted from B's answer (I can [drive]).",
                "'I' is substituted.",
            ],
            "answer": "'Drive' is omitted from B's answer (I can [drive]).",
            "explanation": "Ellipsis = omitting words that are understood from context. 'I can' stands for 'I can drive'.",
        },
        {
            "prompt": "Select the substitution example:",
            "options": [
                "She left and I did too [ ].",
                "I asked him to come but he refused to [ ].",
                "He said he'd help, and he did so.",
                "Can he swim? Yes, he can.",
            ],
            "answer": "He said he'd help, and he did so.",
            "explanation": "'Do so' is a lexical substitution replacing the verb phrase 'help'. Substitution avoids repetition.",
        },
        {
            "prompt": "In 'I could have told you — I nearly did,' what device is used?",
            "options": ["Inversion", "Substitution", "Ellipsis", "Fronting"],
            "answer": "Ellipsis",
            "explanation": "'I nearly did [tell you]' — 'tell you' is omitted because it can be recovered from the previous clause.",
        },
    ],

    "Perfect Aspect — All Forms": [
        {
            "prompt": "Which sentence uses the PAST PERFECT correctly?",
            "options": [
                "By the time she arrived, everyone has left.",
                "By the time she arrived, everyone had left.",
                "By the time she arrives, everyone left.",
                "By the time she arrived, everyone was left.",
            ],
            "answer": "By the time she arrived, everyone had left.",
            "explanation": "Past perfect (had + p.p.) describes an event completed BEFORE another past event.",
        },
        {
            "prompt": "Choose the FUTURE PERFECT: 'By 2030, scientists ___ a cure.'",
            "options": [
                "will find",
                "will have found",
                "have found",
                "had found",
            ],
            "answer": "will have found",
            "explanation": "Future perfect = will have + past participle. Describes an action completed before a future time.",
        },
        {
            "prompt": "What does the PRESENT PERFECT CONTINUOUS emphasise?",
            "options": [
                "A completed action with a present result.",
                "A single completed action in the indefinite past.",
                "The duration or ongoing nature of an action up to now.",
                "A future plan decided in the present.",
            ],
            "answer": "The duration or ongoing nature of an action up to now.",
            "explanation": "E.g. 'She has been working all morning.' — focuses on the duration of the activity.",
        },
    ],
}

# Test exam → levels map (used to assign questions)
EXAM_LEVEL_MAP: dict[str, list[str]] = {
    "A1": ["A1"],
    "A2": ["A1", "A2"],
    "B1": ["A2", "B1"],
    "B2": ["B1", "B2"],
    "C1": ["B2", "C1"],
    "C2": ["C1", "C2"],
}


# ─────────────────────────────────────────────────────────────────────────────

async def seed_questions(db: AsyncSession):
    print("  Clearing existing questions from question_bank...")
    await db.execute(delete(QuestionItem))
    await db.commit()
    print("   question_bank cleared")

    # Load grammar items
    result = await db.execute(select(GrammarItem))
    grammar_items = {g.title: g for g in result.scalars().all()}

    def get_mapped_grammar(title: str):
        t = title.lower()
        if "articles" in t:
            target = "Articles A/An/The"
        elif "present simple" in t or "simple present" in t or "verb 'to be'" in t or "subject pronouns" in t or "possessive adjectives" in t or "there is / there are" in t or "there is/are" in t:
            target = "Present Simple"
        elif "present continuous" in t:
            target = "Present Continuous"
        elif "past simple" in t or "simple past" in t or "used to" in t:
            target = "Past Simple"
        elif "future with will" in t or "will" in t:
            target = "Future with Will"
        elif "comparative" in t and "superlative" not in t:
            target = "Comparatives"
        elif "superlative" in t:
            target = "Superlatives"
        elif "present perfect" in t:
            target = "Present Perfect"
        elif "conditionals: zero and first" in t or "conditional sentences: 1st" in t or "conditionals type 1" in t or "zero and first" in t:
            target = "Conditionals Type 1"
        elif "relative clause" in t:
            target = "Relative Clauses"
        elif "passive voice" in t:
            target = "Passive Voice"
        elif "conditionals type 2/3" in t or "second and third conditional" in t or "third conditional" in t or "subjunctive" in t:
            target = "Conditionals Type 2/3"
        else:
            target = "Present Simple" # Default fallback
        return grammar_items.get(target)

    total = 0
    level_map: dict[str, list] = {}  # level → list of QuestionItem

    for title, questions in GRAMMAR_QUESTIONS.items():
        grammar = get_mapped_grammar(title)
        if not grammar:
            print(f"    ⚠️  Grammar item not found in DB: '{title}' — skipping")
            continue

        for q in questions:
            item = QuestionItem(
                prompt=q["prompt"],
                question_type="mcq",
                options=q["options"],
                answer={"correct": q["answer"]},
                explanation=q["explanation"],
                difficulty_level=grammar.level,
                grammar_id=grammar.id,
                tags=[grammar.topic] if grammar.topic else [],
                is_active=True,
            )
            db.add(item)
            level_map.setdefault(grammar.level, []).append(item)
            total += 1

    await db.commit()
    # Refresh to get IDs
    for items in level_map.values():
        for item in items:
            await db.refresh(item)

    print(f"   {total} questions created")
    return level_map


async def update_test_exams(db: AsyncSession, level_map: dict[str, list]):
    print("  Updating test_exams with question_ids...")
    result = await db.execute(select(TestExam))
    exams = result.scalars().all()

    updated = 0
    for exam in exams:
        # Collect questions for the exam's target levels
        target_levels = EXAM_LEVEL_MAP.get(exam.level, [exam.level])
        candidate_ids = []
        for lvl in target_levels:
            candidate_ids.extend([str(q.id) for q in level_map.get(lvl, [])])

        # Take up to 20 questions per exam
        selected = random.sample(candidate_ids, min(20, len(candidate_ids)))

        exam.question_ids = selected
        exam.is_published = True
        updated += 1

    await db.commit()
    print(f"   {updated} test exams updated with question_ids and published")


async def main():
    print("\n" + "=" * 56)
    print("  Seed Question Bank")
    print("=" * 56 + "\n")

    async with AsyncSessionLocal() as db:
        level_map = await seed_questions(db)
        await update_test_exams(db, level_map)

        # Summary
        total_q = await db.scalar(select(func.count(QuestionItem.id)))
        print(f"\n  question_bank total : {total_q}")
        print("  Done.\n")


if __name__ == "__main__":
    asyncio.run(main())
