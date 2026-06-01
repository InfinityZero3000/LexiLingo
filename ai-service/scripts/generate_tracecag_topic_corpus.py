#!/usr/bin/env python3
"""Generate a large TraceCAG topic corpus and expanded topic catalog.

This script is deterministic and does not call external APIs. It expands the
topic-chat surface area and produces dense quadruple/edge data for TraceCAG.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


AI_SERVICE_ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = AI_SERVICE_ROOT / "data"
DEFAULT_SAMPLE_STORIES = DATA_DIR / "sample_stories.json"
DEFAULT_EXPANDED_STORIES = DATA_DIR / "sample_stories.expanded.json"
DEFAULT_KG_OUTPUT_DIR = DATA_DIR / "kg_output"
DEFAULT_KG_FILE = DATA_DIR / "kg" / "06_tracecag_topic_expansion.json"
DEFAULT_QUADRUPLES_JSONL = DEFAULT_KG_OUTPUT_DIR / "tracecag_topic_quadruples.jsonl"
DEFAULT_EDGES_JSONL = DEFAULT_KG_OUTPUT_DIR / "tracecag_topic_edges.jsonl"
DEFAULT_PREFIX_FULL = DEFAULT_KG_OUTPUT_DIR / "tracecag_knowledge_prefix.full.txt"
DEFAULT_REPORT = DEFAULT_KG_OUTPUT_DIR / "tracecag_topic_corpus_report.json"

CEFR_LEVELS = ("A1", "A2", "B1", "B2", "C1", "C2")


@dataclass(frozen=True)
class TopicBlueprint:
    slug: str
    title: str
    category: str
    level: str
    minutes: int
    setting: str
    role: str
    persona: str
    focus_terms: tuple[str, ...]


CATEGORY_TERMS: dict[str, tuple[str, ...]] = {
    "travel": ("reservation", "arrival", "departure", "itinerary", "ticket", "delay"),
    "work": ("deadline", "priority", "feedback", "milestone", "proposal", "stakeholder"),
    "health": ("symptom", "appointment", "prescription", "dosage", "recovery", "insurance"),
    "food": ("menu", "portion", "ingredient", "order", "flavor", "receipt"),
    "shopping": ("discount", "receipt", "refund", "size", "warranty", "checkout"),
    "finance": ("account", "budget", "payment", "fee", "interest", "statement"),
    "education": ("assignment", "deadline", "lecture", "feedback", "grade", "discussion"),
    "technology": ("device", "settings", "account", "bug", "update", "security"),
    "housing": ("lease", "deposit", "maintenance", "utilities", "neighborhood", "inspection"),
    "services": ("booking", "schedule", "quote", "confirmation", "complaint", "follow-up"),
    "culture": ("exhibit", "tradition", "ticket", "audience", "guide", "event"),
    "leisure": ("practice", "equipment", "membership", "schedule", "reservation", "activity"),
    "social": ("invitation", "introduction", "preference", "agreement", "apology", "plan"),
    "emergency": ("report", "location", "description", "injury", "assistance", "witness"),
    "environment": ("recycling", "pollution", "sustainability", "waste", "energy", "community"),
    "media": ("headline", "interview", "audience", "episode", "script", "source"),
}

GRAMMAR_BY_LEVEL: dict[str, tuple[str, ...]] = {
    "A1": ("Present simple questions", "There is and there are", "Basic imperatives"),
    "A2": ("Polite requests with can and could", "Past simple for events", "Comparatives"),
    "B1": ("Present perfect for experience", "First conditional", "Modals for advice"),
    "B2": ("Second conditional", "Passive voice", "Relative clauses"),
    "C1": ("Hedging and nuance", "Inversion for emphasis", "Advanced conditionals"),
    "C2": ("Register shifts", "Ellipsis and substitution", "Discourse markers"),
}

FUNCTIONS_BY_CATEGORY: dict[str, tuple[str, ...]] = {
    "travel": ("asking for information", "confirming details", "handling delays", "making polite requests"),
    "work": ("giving updates", "clarifying priorities", "negotiating next steps", "summarizing decisions"),
    "health": ("describing symptoms", "asking for advice", "confirming instructions", "expressing concern"),
    "food": ("ordering politely", "asking about ingredients", "making preferences clear", "requesting the bill"),
    "shopping": ("comparing options", "asking for a refund", "checking availability", "explaining a problem"),
    "finance": ("asking about fees", "confirming identity", "explaining transactions", "requesting support"),
    "education": ("asking clarification", "giving opinions", "planning study tasks", "presenting ideas"),
    "technology": ("reporting a bug", "explaining steps", "checking settings", "asking for troubleshooting"),
    "housing": ("asking about terms", "reporting maintenance", "expressing preferences", "confirming costs"),
    "services": ("booking a service", "rescheduling politely", "making a complaint", "confirming details"),
    "culture": ("asking about meaning", "describing impressions", "comparing experiences", "sharing opinions"),
    "leisure": ("making plans", "describing ability", "asking about rules", "inviting someone"),
    "social": ("starting small talk", "showing empathy", "disagreeing politely", "making arrangements"),
    "emergency": ("requesting urgent help", "describing what happened", "giving location", "confirming safety"),
    "environment": ("explaining causes", "suggesting actions", "expressing concern", "persuading others"),
    "media": ("asking interview questions", "summarizing a story", "checking sources", "planning content"),
}

ROLE_BACKGROUNDS: dict[str, str] = {
    "travel": "has helped international visitors solve practical travel problems for years",
    "work": "leads professional conversations with clear expectations and supportive feedback",
    "health": "explains health-related language carefully without giving unsafe medical advice",
    "food": "helps learners handle real dining and food-service conversations naturally",
    "shopping": "supports customers with product details, returns, and practical choices",
    "finance": "explains everyday money language in simple, careful terms",
    "education": "helps learners ask better questions and discuss academic tasks",
    "technology": "turns technical issues into clear step-by-step English conversation",
    "housing": "explains housing terms and practical home-service issues clearly",
    "services": "handles appointments, complaints, and confirmations professionally",
    "culture": "helps visitors discuss events, traditions, and impressions respectfully",
    "leisure": "encourages relaxed conversation around hobbies and activities",
    "social": "guides friendly but natural everyday social interaction",
    "emergency": "keeps questions direct, calm, and focused on safety information",
    "environment": "supports practical discussion about sustainability and local action",
    "media": "helps learners discuss stories, audiences, and content planning",
}

BLUEPRINTS: tuple[TopicBlueprint, ...] = (
    TopicBlueprint("hotel_check_in", "Hotel Check-In Conversation", "travel", "A2", 14, "Hotel reception desk in the evening", "Hotel Receptionist", "Maya", ("room key", "reservation number", "early check-in", "late checkout")),
    TopicBlueprint("asking_for_directions", "Asking for Directions Downtown", "travel", "A1", 10, "Busy city street near a metro station", "Local Guide", "Daniel", ("turn left", "crosswalk", "metro station", "landmark")),
    TopicBlueprint("train_ticket_purchase", "Buying a Train Ticket", "travel", "A2", 12, "Train station ticket counter", "Ticket Agent", "Priya", ("platform", "return ticket", "single ticket", "departure time")),
    TopicBlueprint("lost_luggage_claim", "Lost Luggage Claim", "travel", "B1", 16, "Airport baggage service desk", "Baggage Service Agent", "Omar", ("baggage claim", "suitcase description", "claim form", "tracking number")),
    TopicBlueprint("customs_immigration", "Customs and Immigration Questions", "travel", "B1", 15, "International airport immigration booth", "Immigration Officer", "Elena", ("purpose of visit", "customs declaration", "visa", "duration of stay")),
    TopicBlueprint("city_tour_booking", "Booking a City Tour", "travel", "A2", 12, "Tourist information center", "Tour Coordinator", "Leo", ("guided tour", "pickup point", "walking tour", "museum pass")),
    TopicBlueprint("car_rental_pickup", "Car Rental Pickup", "travel", "B1", 15, "Rental car agency counter", "Rental Agent", "Nora", ("driver's license", "insurance option", "fuel policy", "vehicle inspection")),
    TopicBlueprint("travel_emergency_help", "Travel Emergency Help Desk", "emergency", "B2", 18, "Embassy help desk abroad", "Consular Assistant", "Grace", ("lost passport", "emergency contact", "police report", "temporary document")),
    TopicBlueprint("team_standup", "Daily Team Standup", "work", "B1", 12, "Online team meeting", "Scrum Master", "Ethan", ("blocker", "progress update", "sprint goal", "next task")),
    TopicBlueprint("project_update_meeting", "Project Update Meeting", "work", "B2", 18, "Conference room with project stakeholders", "Project Manager", "Hannah", ("timeline", "risk", "deliverable", "dependency")),
    TopicBlueprint("client_presentation", "Client Presentation Practice", "work", "B2", 20, "Client meeting room", "Account Director", "Victor", ("proposal", "key benefit", "slide deck", "next step")),
    TopicBlueprint("salary_negotiation", "Salary Negotiation Conversation", "work", "C1", 20, "Private meeting with a hiring manager", "Hiring Manager", "Sofia", ("compensation", "benefits package", "market rate", "counteroffer")),
    TopicBlueprint("performance_review", "Performance Review Discussion", "work", "B2", 18, "Manager's office during review season", "Team Manager", "Marcus", ("achievement", "development goal", "feedback", "promotion path")),
    TopicBlueprint("networking_event", "Professional Networking Event", "work", "B1", 15, "Industry meetup reception area", "Event Host", "Iris", ("elevator pitch", "business card", "follow up", "shared interest")),
    TopicBlueprint("remote_work_sync", "Remote Work Sync", "work", "B1", 14, "Video call with a distributed team", "Remote Team Lead", "Noah", ("time zone", "handoff", "availability", "status update")),
    TopicBlueprint("customer_support_call", "Customer Support Call", "services", "B1", 15, "Phone support center", "Support Specialist", "Ava", ("case number", "refund request", "technical issue", "resolution")),
    TopicBlueprint("pharmacy_visit", "At the Pharmacy", "health", "A2", 12, "Neighborhood pharmacy counter", "Pharmacist", "Lina", ("dosage", "side effect", "over-the-counter", "refill")),
    TopicBlueprint("dental_appointment", "Dental Appointment Checkup", "health", "B1", 15, "Dental clinic reception and exam room", "Dentist", "Dr. Kim", ("toothache", "cleaning", "cavity", "appointment slot")),
    TopicBlueprint("mental_health_checkin", "Mental Health Check-In", "health", "B2", 18, "Counseling center intake room", "Wellness Counselor", "Jamie", ("stress level", "coping strategy", "sleep pattern", "support network")),
    TopicBlueprint("fitness_class_signup", "Fitness Class Sign-Up", "health", "A2", 12, "Gym front desk", "Fitness Coach", "Ben", ("membership", "trial class", "warm-up", "schedule")),
    TopicBlueprint("health_insurance_call", "Health Insurance Phone Call", "finance", "B2", 18, "Insurance support phone line", "Insurance Advisor", "Mila", ("coverage", "claim", "deductible", "policy number")),
    TopicBlueprint("emergency_room_triage", "Emergency Room Triage", "emergency", "B2", 16, "Hospital emergency reception", "Triage Nurse", "Nurse Patel", ("urgent symptom", "pain level", "medical history", "waiting time")),
    TopicBlueprint("grocery_market", "Grocery Market Shopping", "food", "A1", 10, "Local grocery market", "Market Vendor", "Rosa", ("fresh produce", "price per kilo", "cash payment", "shopping list")),
    TopicBlueprint("cooking_class", "Cooking Class Instructions", "food", "A2", 14, "Community cooking classroom", "Cooking Instructor", "Chef Marco", ("recipe", "chop", "simmer", "serving size")),
    TopicBlueprint("food_delivery_problem", "Food Delivery Problem", "services", "B1", 15, "Chat with a food delivery support agent", "Delivery Support Agent", "Tara", ("missing item", "delivery address", "refund", "order number")),
    TopicBlueprint("bakery_order", "Ordering at a Bakery", "food", "A1", 10, "Small bakery in the morning", "Baker", "Claire", ("croissant", "loaf", "slice", "takeaway bag")),
    TopicBlueprint("dietary_restrictions", "Explaining Dietary Restrictions", "food", "B1", 14, "Restaurant table before ordering", "Server", "Mateo", ("allergy", "vegetarian option", "gluten-free", "ingredient list")),
    TopicBlueprint("dinner_party_planning", "Planning a Dinner Party", "social", "B1", 16, "Friend's kitchen while planning a meal", "Friend Host", "Olivia", ("guest list", "main dish", "bring dessert", "set the table")),
    TopicBlueprint("bank_account_opening", "Opening a Bank Account", "finance", "B1", 16, "Bank customer service desk", "Bank Officer", "Ms. Lee", ("current account", "identification", "monthly fee", "debit card")),
    TopicBlueprint("phone_plan_subscription", "Choosing a Phone Plan", "shopping", "B1", 15, "Mobile phone store", "Sales Consultant", "Ryan", ("data plan", "contract", "coverage", "monthly bill")),
    TopicBlueprint("returning_electronics", "Returning Electronics", "shopping", "B1", 14, "Electronics store returns counter", "Returns Clerk", "Nina", ("warranty", "defect", "exchange", "proof of purchase")),
    TopicBlueprint("online_order_support", "Online Order Support Chat", "services", "A2", 12, "Online customer service chat", "Support Agent", "Kai", ("tracking number", "shipping delay", "order status", "confirmation email")),
    TopicBlueprint("comparing_prices", "Comparing Prices at a Store", "shopping", "A2", 12, "Department store aisle", "Store Assistant", "Ella", ("discount", "cheaper option", "brand", "quality")),
    TopicBlueprint("budgeting_conversation", "Monthly Budget Planning", "finance", "B2", 18, "Kitchen table with bills and notes", "Financial Coach", "Sam", ("fixed expense", "savings goal", "spending habit", "emergency fund")),
    TopicBlueprint("loan_application", "Applying for a Small Loan", "finance", "C1", 20, "Bank lending office", "Loan Advisor", "David", ("credit score", "interest rate", "repayment plan", "collateral")),
    TopicBlueprint("tax_appointment", "Tax Appointment Questions", "finance", "B2", 18, "Tax advisor's office", "Tax Advisor", "Amelia", ("deduction", "income statement", "filing deadline", "receipt")),
    TopicBlueprint("university_orientation", "University Orientation", "education", "B1", 16, "Campus orientation desk", "Student Ambassador", "Chloe", ("course registration", "campus map", "student ID", "orientation schedule")),
    TopicBlueprint("library_assistance", "Asking for Library Help", "education", "A2", 12, "University library information desk", "Librarian", "Mr. Brooks", ("library card", "renew a book", "database", "quiet area")),
    TopicBlueprint("parent_teacher_meeting", "Parent-Teacher Meeting", "education", "B1", 16, "School classroom after class", "Teacher", "Ms. Carter", ("progress", "homework routine", "participation", "learning goal")),
    TopicBlueprint("study_group_planning", "Study Group Planning", "education", "A2", 12, "Cafe near campus", "Classmate", "Mina", ("study session", "chapter review", "practice test", "shared notes")),
    TopicBlueprint("exam_preparation", "Exam Preparation Strategy", "education", "B2", 18, "Tutor room before an exam", "Exam Coach", "Ken", ("revision schedule", "mock exam", "weak area", "time management")),
    TopicBlueprint("scholarship_interview", "Scholarship Interview", "education", "C1", 20, "Formal interview panel room", "Scholarship Panelist", "Dr. Evans", ("academic achievement", "community service", "career goal", "leadership")),
    TopicBlueprint("classroom_debate", "Classroom Debate Practice", "education", "B2", 18, "Language classroom debate circle", "Debate Moderator", "Anna", ("argument", "evidence", "rebuttal", "conclusion")),
    TopicBlueprint("password_reset_support", "Password Reset Support", "technology", "A2", 12, "Tech support chat window", "IT Support Agent", "Mason", ("verification code", "reset link", "username", "security question")),
    TopicBlueprint("app_bug_report", "Reporting an App Bug", "technology", "B1", 15, "In-app support form", "QA Support Specialist", "Luca", ("screenshot", "error message", "steps to reproduce", "app version")),
    TopicBlueprint("data_privacy_settings", "Changing Data Privacy Settings", "technology", "B2", 18, "Account settings screen", "Privacy Specialist", "Riley", ("privacy setting", "data sharing", "permission", "two-factor authentication")),
    TopicBlueprint("buying_laptop", "Buying a Laptop", "shopping", "B1", 15, "Computer store showroom", "Tech Sales Advisor", "Harper", ("processor", "memory", "battery life", "warranty")),
    TopicBlueprint("cybersecurity_awareness", "Cybersecurity Awareness Chat", "technology", "B2", 18, "Company security training room", "Security Trainer", "Morgan", ("phishing email", "strong password", "suspicious link", "backup")),
    TopicBlueprint("ai_product_demo", "AI Product Demo", "technology", "C1", 20, "Software demo call", "Product Specialist", "Taylor", ("workflow automation", "model output", "integration", "use case")),
    TopicBlueprint("software_sprint_planning", "Software Sprint Planning", "work", "C1", 20, "Agile planning meeting", "Engineering Manager", "Jordan", ("user story", "acceptance criteria", "estimate", "technical risk")),
    TopicBlueprint("moving_day_coordination", "Moving Day Coordination", "housing", "A2", 14, "Apartment building lobby on moving day", "Moving Coordinator", "Pat", ("moving truck", "elevator booking", "fragile box", "new address")),
    TopicBlueprint("plumber_appointment", "Booking a Plumber", "services", "B1", 14, "Phone call with a repair service", "Plumber Dispatcher", "Alexis", ("leak", "appointment window", "service fee", "repair estimate")),
    TopicBlueprint("utility_bill_dispute", "Utility Bill Dispute", "housing", "B2", 18, "Utility company customer service line", "Billing Specialist", "Renee", ("meter reading", "billing cycle", "overcharge", "payment plan")),
    TopicBlueprint("cleaning_service_booking", "Cleaning Service Booking", "services", "A2", 12, "Home service booking call", "Cleaning Coordinator", "Penny", ("deep cleaning", "available slot", "cleaning supplies", "service package")),
    TopicBlueprint("neighborhood_complaint", "Neighborhood Complaint", "housing", "B2", 18, "Apartment management office", "Building Manager", "Mr. Singh", ("noise complaint", "quiet hours", "tenant notice", "shared space")),
    TopicBlueprint("home_internet_installation", "Home Internet Installation", "technology", "B1", 15, "Home visit by internet technician", "Internet Technician", "Chris", ("router", "installation window", "signal strength", "service plan")),
    TopicBlueprint("museum_visit", "Museum Visit Conversation", "culture", "A2", 12, "Museum entrance hall", "Museum Guide", "Isabella", ("exhibition", "audio guide", "ticket desk", "gallery")),
    TopicBlueprint("sports_club_signup", "Joining a Sports Club", "leisure", "A2", 12, "Community sports club reception", "Club Coordinator", "Max", ("membership fee", "training session", "equipment", "team schedule")),
    TopicBlueprint("volunteering_event", "Volunteering Event Sign-Up", "social", "B1", 16, "Community center volunteer desk", "Volunteer Organizer", "Aisha", ("volunteer shift", "community project", "sign-up form", "orientation")),
    TopicBlueprint("news_interview", "Giving a Short News Interview", "media", "C1", 20, "Local news recording setup", "Journalist", "Megan", ("main point", "follow-up question", "public reaction", "quote")),
)


def slugify(value: str) -> str:
    text = value.strip().lower()
    text = re.sub(r"['’]", "", text)
    text = re.sub(r"[^a-z0-9]+", "_", text)
    return re.sub(r"_+", "_", text).strip("_") or "item"


def load_json(path: Path, default: Any | None = None) -> Any:
    if not path.exists():
        if default is not None:
            return default
        raise FileNotFoundError(path)
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def atomic_write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp_name, path)
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)


def atomic_write_json(path: Path, payload: Any) -> None:
    atomic_write_text(path, json.dumps(payload, ensure_ascii=False, indent=2) + "\n")


def make_term_definition(term: str, title: str) -> str:
    return f"A useful expression or concept for handling '{term}' in the {title.lower()} scenario"


def make_example(term: str, title: str) -> str:
    return f"Could you help me with the {term} during this {title.lower()}?"


def unique_terms(blueprint: TopicBlueprint, count: int = 10) -> list[str]:
    words = [
        word
        for word in re.findall(r"[a-zA-Z][a-zA-Z']+", blueprint.title.lower())
        if word not in {"and", "for", "the", "with", "at", "a", "an", "to", "of"}
    ]
    candidates = list(blueprint.focus_terms) + list(CATEGORY_TERMS.get(blueprint.category, ())) + words
    seen: set[str] = set()
    terms: list[str] = []
    for item in candidates:
        term = item.strip().lower().replace("_", " ")
        if len(term) < 3 or term in seen:
            continue
        seen.add(term)
        terms.append(term)
        if len(terms) == count:
            break
    while len(terms) < count:
        filler = f"{blueprint.category} phrase {len(terms) + 1}"
        terms.append(filler)
    return terms


def story_from_blueprint(blueprint: TopicBlueprint) -> dict[str, Any]:
    terms = unique_terms(blueprint)
    grammar_points = GRAMMAR_BY_LEVEL[blueprint.level]
    functions = FUNCTIONS_BY_CATEGORY[blueprint.category]
    story_id = f"story_{blueprint.slug}"
    title = blueprint.title
    setting = blueprint.setting

    return {
        "story_id": story_id,
        "title": {
            "en": title,
            "vi": f"Chu de: {title}",
        },
        "difficulty_level": blueprint.level,
        "category": blueprint.category,
        "estimated_minutes": blueprint.minutes,
        "context_description": {
            "setting": setting,
            "scenario": (
                f"A learner practices a realistic {title.lower()} interaction. "
                f"The conversation focuses on clear questions, practical vocabulary, "
                f"and natural follow-up responses."
            ),
            "objectives": [
                f"Use topic vocabulary for {title.lower()}",
                f"Practice {functions[0]} and {functions[1]}",
                f"Use {grammar_points[0].lower()} accurately",
                "Respond naturally to follow-up questions",
            ],
        },
        "role_persona": {
            "name": blueprint.persona,
            "role": blueprint.role,
            "personality": "Helpful, patient, practical, and encouraging",
            "speaking_style": "Clear, natural, and level-appropriate with gentle corrections",
            "background": f"{blueprint.persona} {ROLE_BACKGROUNDS.get(blueprint.category, 'helps learners practice practical English')}.",
        },
        "vocabulary_list": [
            {
                "term": term,
                "definition": make_term_definition(term, title),
                "example_in_story": make_example(term, title),
                "part_of_speech": "noun phrase" if " " in term else "noun",
            }
            for term in terms
        ],
        "grammar_points": [
            {
                "grammar_structure": grammar,
                "explanation": f"Use {grammar.lower()} to keep the {title.lower()} conversation clear and accurate.",
                "usage_in_story": f"This structure helps the learner ask, explain, or respond during {title.lower()}.",
                "examples": [
                    f"Could you explain the {terms[0]}?",
                    f"I need to confirm the {terms[1]}.",
                    f"If there is a problem, I will ask about the {terms[2]}.",
                ],
            }
            for grammar in grammar_points
        ],
        "conversation_flow": {
            "opening_prompt": f"Hello! Welcome. How can I help you with your {title.lower()} today?",
            "key_milestones": [
                "Greet and explain the situation",
                f"Ask about {terms[0]}",
                f"Clarify {terms[1]} or {terms[2]}",
                "Confirm the next step",
                "Close politely",
            ],
            "closing_scenarios": [
                "Thanks, that answers my question.",
                "Great, I understand the next step now.",
                "Could you send me the details in writing?",
            ],
        },
        "suggested_prompts": [
            f"I need help with the {terms[0]}.",
            f"Can you explain the {terms[1]}?",
            f"What should I do next in this {title.lower()}?",
        ],
        "tags": [
            blueprint.category,
            blueprint.level,
            "tracecag",
            "topic_expansion",
            slugify(title),
        ],
        "is_published": True,
    }


def concept_id(prefix: str, value: str) -> str:
    return f"{prefix}:{slugify(value)}"


def kg_concept(concepts: dict[str, dict[str, Any]], cid: str, title: str, level: str, keywords: Iterable[str]) -> None:
    if cid in concepts:
        existing = concepts[cid]
        existing_keywords = set(str(existing.get("keywords", "")).split())
        existing_keywords.update(slugify(k).replace("_", " ") for k in keywords)
        existing["keywords"] = " ".join(sorted(token for kw in existing_keywords for token in kw.split()))
        return
    keyword_text = " ".join(dict.fromkeys(token for kw in keywords for token in slugify(str(kw)).split("_") if token))
    concepts[cid] = {
        "id": cid,
        "title": title,
        "level": level,
        "keywords": keyword_text,
    }


def context(source_id: str, evidence: str, confidence: float = 0.92) -> dict[str, Any]:
    return {
        "evidence": evidence,
        "source_id": source_id,
        "confidence": confidence,
        "uncertain": False,
        "domain": "topic_chat",
        "pipeline": "TraceCAG",
    }


def add_quad(
    quadruples: list[dict[str, Any]],
    edges: list[dict[str, Any]],
    subject: str,
    predicate: str,
    obj: str,
    evidence: str,
    source_id: str,
    confidence: float = 0.92,
) -> None:
    quadruples.append(
        {
            "subject": subject,
            "predicate": predicate,
            "object": obj,
            "context": context(source_id, evidence, confidence),
        }
    )
    if ":" in obj and not obj.startswith(("http:", "https:")):
        edges.append(
            {
                "source": subject,
                "target": obj,
                "relation": predicate,
                "confidence": confidence,
                "source_id": source_id,
                "uncertain": False,
            }
        )


def generate_tracecag_graph(stories: list[dict[str, Any]]) -> tuple[dict[str, Any], list[dict[str, Any]], list[dict[str, Any]]]:
    concepts: dict[str, dict[str, Any]] = {}
    kg_edges: dict[tuple[str, str, str], dict[str, str]] = {}
    quadruples: list[dict[str, Any]] = []
    raw_edges: list[dict[str, Any]] = []

    for story in stories:
        sid = story["story_id"]
        title = story["title"]["en"]
        level = story["difficulty_level"]
        category = story["category"]
        source_id = f"TraceCAG_topic_{sid}"
        topic_cid = concept_id("topic", sid)
        domain_cid = concept_id("domain", category)
        cefr_cid = concept_id("cefrlevel", level)
        scenario_cid = concept_id("scenario", sid)
        persona_cid = concept_id("persona", story["role_persona"]["role"])

        kg_concept(concepts, topic_cid, title, level, [title, category, sid])
        kg_concept(concepts, domain_cid, category.replace("_", " ").title(), level, [category])
        kg_concept(concepts, cefr_cid, level, level, [level, "cefr"])
        kg_concept(concepts, scenario_cid, f"{title} Scenario", level, [title, "scenario", category])
        kg_concept(concepts, persona_cid, story["role_persona"]["role"], level, [story["role_persona"]["role"], story["role_persona"]["name"]])

        evidence_base = f"{title}: {story['context_description']['scenario']}"
        metadata_edges = (
            (topic_cid, "belongs_to_domain", domain_cid),
            (topic_cid, "has_cefr_level", cefr_cid),
            (topic_cid, "uses_scenario", scenario_cid),
            (topic_cid, "role_played_by", persona_cid),
            (persona_cid, "supports_topic", topic_cid),
            (scenario_cid, "belongs_to_domain", domain_cid),
            (scenario_cid, "has_cefr_level", cefr_cid),
            (domain_cid, "includes_topic", topic_cid),
        )
        for src, rel, dst in metadata_edges:
            add_quad(quadruples, raw_edges, src, rel, dst, evidence_base, source_id, 0.95)

        add_quad(quadruples, raw_edges, topic_cid, "defined_as", story["context_description"]["scenario"], evidence_base, source_id)
        add_quad(quadruples, raw_edges, persona_cid, "defined_as", story["role_persona"]["background"], evidence_base, source_id)

        vocab_ids: list[str] = []
        for index, item in enumerate(story["vocabulary_list"]):
            term = item["term"]
            vid = concept_id("vocabulary", f"{sid}_{term}")
            vocab_ids.append(vid)
            error_id = concept_id("errorpattern", f"{sid}_{term}_misuse")
            phrase_id = concept_id("phrase", f"{sid}_{term}_request")
            collocation_id = concept_id("collocation", f"{sid}_{term}_collocation")
            kg_concept(concepts, vid, term.title(), level, [term, title, category])
            kg_concept(concepts, error_id, f"{term.title()} Misuse", level, [term, "error", "learner"])
            kg_concept(concepts, phrase_id, f"{term.title()} Request Phrase", level, [term, "request", "phrase"])
            kg_concept(concepts, collocation_id, f"{term.title()} Collocation", level, [term, "collocation", category])
            target_next = vocab_ids[index - 1] if index > 0 else scenario_cid

            evidence = item["example_in_story"]
            for src, rel, dst, conf in (
                (topic_cid, "contains", vid, 0.96),
                (vid, "belongs_to_domain", domain_cid, 0.93),
                (vid, "has_cefr_level", cefr_cid, 0.93),
                (vid, "used_in_scenario", scenario_cid, 0.94),
                (vid, "introduced_by", persona_cid, 0.9),
                (vid, "practiced_with", phrase_id, 0.93),
                (phrase_id, "requires", vid, 0.91),
                (vid, "has_collocation", collocation_id, 0.91),
                (collocation_id, "related_to", vid, 0.91),
                (vid, "has_error_pattern", error_id, 0.88),
                (error_id, "corrected_by", phrase_id, 0.88),
                (vid, "related_to", target_next, 0.87),
            ):
                add_quad(quadruples, raw_edges, src, rel, dst, evidence, source_id, conf)
            add_quad(quadruples, raw_edges, vid, "defined_as", item["definition"], evidence, source_id, 0.94)
            add_quad(quadruples, raw_edges, vid, "example_sentence", evidence, evidence, source_id, 0.94)
            add_quad(quadruples, raw_edges, error_id, "example_sentence", f"Learner may misuse '{term}' without enough context.", evidence, source_id, 0.84)

        grammar_ids: list[str] = []
        for index, item in enumerate(story["grammar_points"]):
            grammar = item["grammar_structure"]
            gid = concept_id("grammar", f"{sid}_{grammar}")
            grammar_ids.append(gid)
            kg_concept(concepts, gid, grammar, level, [grammar, title, category])
            evidence = item["usage_in_story"]
            linked_vocab = vocab_ids[index % len(vocab_ids)]
            for src, rel, dst, conf in (
                (topic_cid, "practices", gid, 0.95),
                (gid, "has_cefr_level", cefr_cid, 0.94),
                (gid, "belongs_to_domain", domain_cid, 0.88),
                (gid, "used_in_scenario", scenario_cid, 0.91),
                (gid, "supports_vocabulary", linked_vocab, 0.88),
                (linked_vocab, "reinforced_by", gid, 0.88),
                (gid, "introduced_by", persona_cid, 0.85),
            ):
                add_quad(quadruples, raw_edges, src, rel, dst, evidence, source_id, conf)
            add_quad(quadruples, raw_edges, gid, "defined_as", item["explanation"], evidence, source_id, 0.93)
            for example in item["examples"]:
                add_quad(quadruples, raw_edges, gid, "example_sentence", example, evidence, source_id, 0.93)

        functions = FUNCTIONS_BY_CATEGORY.get(category, FUNCTIONS_BY_CATEGORY["social"])
        for index, function in enumerate(functions):
            fid = concept_id("function", f"{sid}_{function}")
            kg_concept(concepts, fid, function.title(), level, [function, category, title])
            linked_vocab = vocab_ids[index % len(vocab_ids)]
            linked_grammar = grammar_ids[index % len(grammar_ids)]
            evidence = f"The learner needs {function} during {title.lower()}."
            for src, rel, dst, conf in (
                (topic_cid, "requires_function", fid, 0.94),
                (fid, "belongs_to_domain", domain_cid, 0.91),
                (fid, "has_cefr_level", cefr_cid, 0.9),
                (fid, "uses_vocabulary", linked_vocab, 0.9),
                (fid, "uses_grammar", linked_grammar, 0.9),
                (fid, "used_in_scenario", scenario_cid, 0.91),
                (persona_cid, "models_function", fid, 0.88),
            ):
                add_quad(quadruples, raw_edges, src, rel, dst, evidence, source_id, conf)
            add_quad(quadruples, raw_edges, fid, "defined_as", f"Language used for {function} in {title.lower()}.", evidence, source_id)

        phrase_templates = (
            "Could you explain the {term}?",
            "I need to confirm the {term}.",
            "What happens if there is a problem with the {term}?",
            "Could you repeat the details about the {term}?",
            "I would like to ask about the {term}.",
            "Is the {term} included in the next step?",
            "Can we check the {term} together?",
            "That helps me understand the {term}.",
        )
        for index, template in enumerate(phrase_templates):
            term = story["vocabulary_list"][index % len(vocab_ids)]["term"]
            pid = concept_id("phrase", f"{sid}_practice_phrase_{index + 1}")
            kg_concept(concepts, pid, template.format(term=term), level, [term, "phrase", title])
            linked_vocab = vocab_ids[index % len(vocab_ids)]
            linked_function = concept_id("function", f"{sid}_{functions[index % len(functions)]}")
            evidence = template.format(term=term)
            for src, rel, dst, conf in (
                (topic_cid, "has_practice_phrase", pid, 0.94),
                (pid, "uses_vocabulary", linked_vocab, 0.94),
                (pid, "performs_function", linked_function, 0.9),
                (pid, "has_cefr_level", cefr_cid, 0.9),
                (pid, "used_in_scenario", scenario_cid, 0.9),
            ):
                add_quad(quadruples, raw_edges, src, rel, dst, evidence, source_id, conf)
            add_quad(quadruples, raw_edges, pid, "example_sentence", evidence, evidence, source_id)

        for objective in story["context_description"]["objectives"]:
            oid = concept_id("objective", f"{sid}_{objective}")
            kg_concept(concepts, oid, objective, level, [objective, title, category])
            add_quad(quadruples, raw_edges, topic_cid, "has_learning_objective", oid, objective, source_id, 0.93)
            add_quad(quadruples, raw_edges, oid, "belongs_to_domain", domain_cid, objective, source_id, 0.9)
            add_quad(quadruples, raw_edges, oid, "has_cefr_level", cefr_cid, objective, source_id, 0.9)
            add_quad(quadruples, raw_edges, oid, "defined_as", objective, objective, source_id, 0.9)

        for milestone in story["conversation_flow"]["key_milestones"]:
            mid = concept_id("milestone", f"{sid}_{milestone}")
            kg_concept(concepts, mid, milestone, level, [milestone, title, category])
            add_quad(quadruples, raw_edges, topic_cid, "has_conversation_milestone", mid, milestone, source_id, 0.93)
            add_quad(quadruples, raw_edges, mid, "used_in_scenario", scenario_cid, milestone, source_id, 0.9)
            add_quad(quadruples, raw_edges, persona_cid, "guides_milestone", mid, milestone, source_id, 0.88)

    for edge in raw_edges:
        key = (edge["source"], edge["target"], edge["relation"])
        kg_edges[key] = {
            "from": edge["source"],
            "to": edge["target"],
            "relation": edge["relation"],
        }

    graph = {
        "version": "2.0.0",
        "description": "TraceCAG expanded topic knowledge graph for LexiLingo topic chat",
        "concepts": sorted(concepts.values(), key=lambda item: item["id"]),
        "edges": sorted(kg_edges.values(), key=lambda item: (item["from"], item["relation"], item["to"])),
    }
    return graph, quadruples, raw_edges


def render_prefix(graph: dict[str, Any], edges: list[dict[str, Any]]) -> str:
    concepts = {item["id"]: item for item in graph["concepts"]}
    lines = ["[LEXILINGO TRACECAG KNOWLEDGE BASE]"]
    for edge in edges:
        src = concepts.get(edge["source"])
        dst = concepts.get(edge["target"])
        if not src or not dst:
            continue
        lines.append(
            f"- ({src['title']} ({node_type(edge['source'])})) "
            f"-[{edge['relation']}]-> "
            f"({dst['title']} ({node_type(edge['target'])})) "
            f"[Source: {edge['source_id']}; confidence={edge['confidence']:.2f}]"
        )
    return "\n".join(lines) + "\n"


def node_type(node_id: str) -> str:
    prefix = node_id.split(":", 1)[0]
    return {
        "topic": "Topic",
        "domain": "Domain",
        "cefrlevel": "CEFRLevel",
        "scenario": "Scenario",
        "persona": "Persona",
        "vocabulary": "Vocabulary",
        "errorpattern": "ErrorPattern",
        "phrase": "Phrase",
        "collocation": "Collocation",
        "grammar": "Grammar",
        "function": "Function",
        "objective": "Objective",
        "milestone": "Milestone",
    }.get(prefix, "Concept")


def load_existing_stories(path: Path) -> list[dict[str, Any]]:
    payload = load_json(path, default={"stories": []})
    stories = payload.get("stories", payload) if isinstance(payload, dict) else payload
    if not isinstance(stories, list):
        raise ValueError(f"Expected a story list in {path}")
    return [story for story in stories if isinstance(story, dict) and story.get("story_id")]


def merge_stories(existing: list[dict[str, Any]], generated: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_id = {story["story_id"]: story for story in existing}
    for story in generated:
        by_id[story["story_id"]] = story
    existing_ids = [story["story_id"] for story in existing]
    merged = [by_id[sid] for sid in existing_ids if sid in by_id]
    for story in generated:
        if story["story_id"] not in existing_ids:
            merged.append(story)
    return merged


def validate_outputs(stories: list[dict[str, Any]], graph: dict[str, Any], quadruples: list[dict[str, Any]], edges: list[dict[str, Any]], min_lines: int) -> dict[str, Any]:
    story_ids = [story["story_id"] for story in stories]
    concept_ids = [item["id"] for item in graph["concepts"]]
    concept_set = set(concept_ids)
    dangling_edges = [
        edge for edge in graph["edges"]
        if edge["from"] not in concept_set or edge["to"] not in concept_set
    ]
    duplicate_story_ids = len(story_ids) - len(set(story_ids))
    duplicate_concepts = len(concept_ids) - len(set(concept_ids))
    duplicate_edges = len(graph["edges"]) - len({(e["from"], e["to"], e["relation"]) for e in graph["edges"]})
    generated_story_count = len([story for story in stories if "topic_expansion" in (story.get("tags") or [])])
    ok = (
        generated_story_count >= 50
        and len(quadruples) > min_lines
        and len(edges) > min_lines
        and duplicate_story_ids == 0
        and duplicate_concepts == 0
        and duplicate_edges == 0
        and not dangling_edges
    )
    return {
        "ok": ok,
        "total_stories": len(stories),
        "generated_topic_count": generated_story_count,
        "quadruple_lines": len(quadruples),
        "edge_lines": len(edges),
        "kg_concepts": len(graph["concepts"]),
        "kg_edges": len(graph["edges"]),
        "duplicate_story_ids": duplicate_story_ids,
        "duplicate_concepts": duplicate_concepts,
        "duplicate_edges": duplicate_edges,
        "dangling_edges": len(dangling_edges),
        "min_required_lines": min_lines,
    }


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    text = "".join(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n" for row in rows)
    atomic_write_text(path, text)


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Generate TraceCAG expanded topic corpus.")
    parser.add_argument("--sample-stories", type=Path, default=DEFAULT_SAMPLE_STORIES)
    parser.add_argument("--expanded-stories", type=Path, default=DEFAULT_EXPANDED_STORIES)
    parser.add_argument("--kg-file", type=Path, default=DEFAULT_KG_FILE)
    parser.add_argument("--quadruples-jsonl", type=Path, default=DEFAULT_QUADRUPLES_JSONL)
    parser.add_argument("--edges-jsonl", type=Path, default=DEFAULT_EDGES_JSONL)
    parser.add_argument("--prefix-full", type=Path, default=DEFAULT_PREFIX_FULL)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--min-lines", type=int, default=10_000)
    parser.add_argument("--merge-stories", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser


def run(args: argparse.Namespace) -> dict[str, Any]:
    existing = load_existing_stories(args.sample_stories)
    generated = [story_from_blueprint(blueprint) for blueprint in BLUEPRINTS]
    merged_stories = merge_stories(existing, generated)
    graph, quadruples, edges = generate_tracecag_graph(generated)
    report = validate_outputs(merged_stories, graph, quadruples, edges, args.min_lines)
    report["blueprint_count"] = len(BLUEPRINTS)
    report["pipeline"] = "TraceCAG"

    if not report["ok"]:
        raise RuntimeError(f"Generated corpus failed validation: {report}")

    if not args.dry_run:
        stories_payload = {"stories": merged_stories}
        atomic_write_json(args.expanded_stories, stories_payload)
        if args.merge_stories:
            atomic_write_json(args.sample_stories, stories_payload)
        atomic_write_json(args.kg_file, graph)
        write_jsonl(args.quadruples_jsonl, quadruples)
        write_jsonl(args.edges_jsonl, edges)
        atomic_write_text(args.prefix_full, render_prefix(graph, edges))
        atomic_write_json(args.report, report)

    return report


def main() -> None:
    parser = build_arg_parser()
    args = parser.parse_args()
    report = run(args)
    print(
        "TraceCAG topic corpus generated: "
        f"stories={report['total_stories']} "
        f"new_topics={report['generated_topic_count']} "
        f"quadruples={report['quadruple_lines']} "
        f"edges={report['edge_lines']} "
        f"kg_concepts={report['kg_concepts']} "
        f"kg_edges={report['kg_edges']}"
    )


if __name__ == "__main__":
    main()
