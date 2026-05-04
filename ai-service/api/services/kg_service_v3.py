"""V3 Knowledge Graph service.

This is a thin interface for:
- Expanding concepts (graph hops)
- Writing/learning edges after each interaction

Uses KuzuDB as the graph database backend.
Singleton pattern ensures the database is created once and reused.
"""

from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional, Tuple
import os
import shutil
import time
import json
import re

import kuzu

from api.core.config import settings
from api.models.v3_schemas import KGHits, KGExpandedNode, KGPath

logger = logging.getLogger(__name__)

# ── Singleton instance ────────────────────────────────────────────────────────
_kg_instance: Optional["KnowledgeGraphServiceV3"] = None


def get_kg_service() -> "KnowledgeGraphServiceV3":
    """Get or create the singleton KnowledgeGraphServiceV3 instance."""
    global _kg_instance
    if _kg_instance is None:
        _kg_instance = KnowledgeGraphServiceV3()
    return _kg_instance


class KnowledgeGraphServiceV3:
    """KuzuDB-backed KG service for V3 pipeline (singleton via get_kg_service())."""

    def __init__(self) -> None:
        db_path = getattr(settings, "KUZU_DB_PATH", None) or os.path.join(
            os.path.dirname(__file__), "..", "..", "data", "kuzu"
        )
        self._db_path = os.path.abspath(db_path)
        self._recovery_attempted = False

        # ── In-memory caches (Phase 1) ─────────────────────────────────────
        # _concepts_cache: None = cold (not yet built); Dict = warm
        self._concepts_cache: Optional[Dict[str, Dict[str, str]]] = None
        # inverted index: keyword → [concept_id, ...]  (O(1) lookup)
        self._keyword_index: Dict[str, List[str]] = {}
        # TF-IDF structures (Phase 3, pure Python)
        self._tfidf_concept_ids: List[str] = []
        self._tfidf_idf: Dict[str, float] = {}
        self._tfidf_vectors: List[Dict[str, float]] = []
        # ──────────────────────────────────────────────────────────────────

        # Create parent directory if doesn't exist
        parent_dir = os.path.dirname(self._db_path)
        os.makedirs(parent_dir, exist_ok=True)
        
        # Only destroy and recreate if the DB is corrupted or missing.
        # Check if schema already exists to avoid unnecessary re-seed.
        needs_seed = False
        if os.path.exists(self._db_path) and not os.path.isdir(self._db_path):
            os.remove(self._db_path)
            needs_seed = True
        elif not os.path.isdir(self._db_path):
            needs_seed = True
        
        try:
            self._db = kuzu.Database(self._db_path)
            self._conn = kuzu.Connection(self._db)
            self._ensure_schema()
            
            # Only seed if this is a fresh database
            if needs_seed or self.get_concept_count() == 0:
                logger.info("[KG] Seeding default knowledge graph...")
                self._seed_default_graph()
            else:
                logger.info(f"[KG] Reusing existing KG with {self.get_concept_count()} concepts")

            # Keep KG in sync with optional external knowledge bundle.
            self._sync_external_knowledge()

            # Warm in-memory caches after all DB writes are done.
            self._build_concept_cache()
        except Exception as e:
            logger.warning(f"[KG] DB may be corrupted, rebuilding: {e}")
            self._hard_rebuild_db(reason=str(e))

    def _hard_rebuild_db(self, reason: str = "unknown") -> None:
        """Rebuild Kuzu DB from scratch when corruption is detected."""
        logger.warning("[KG] Hard rebuild triggered: %s", reason)
        if os.path.isdir(self._db_path):
            if "lock" in reason.lower():
                logger.error("[KG] DB locked, cannot rebuild safely: %s", self._db_path)
                raise RuntimeError(reason)
            ts = int(time.time() * 1000)
            quarantine = f"{self._db_path}.corrupt.{ts}"
            suffix = 1
            while os.path.exists(quarantine):
                quarantine = f"{self._db_path}.corrupt.{ts}.{suffix}"
                suffix += 1
            try:
                os.rename(self._db_path, quarantine)
                logger.warning("[KG] Quarantined corrupted DB to %s", quarantine)
            except Exception:
                shutil.rmtree(self._db_path, ignore_errors=True)
        elif os.path.exists(self._db_path):
            os.remove(self._db_path)

        os.makedirs(self._db_path, exist_ok=True)
        self._db = kuzu.Database(self._db_path)
        self._conn = kuzu.Connection(self._db)
        self._ensure_schema()
        self._seed_default_graph()
        self._sync_external_knowledge()
        self._build_concept_cache()
        self._recovery_attempted = True

    def _is_corruption_error(self, exc: Exception) -> bool:
        text = str(exc).lower()
        return (
            "reading past the end of the file" in text
            or "corrupt" in text
            or "checksum" in text
            or "invalid" in text
        )

    def _recover_and_retry(self, op_name: str) -> bool:
        if self._recovery_attempted:
            return False
        try:
            logger.warning("[KG] Attempting one-time recovery for %s", op_name)
            self._hard_rebuild_db(reason=f"runtime failure during {op_name}")
            return True
        except Exception as rebuild_exc:
            logger.error("[KG] Recovery failed for %s: %s", op_name, rebuild_exc)
            return False

    def _ensure_schema(self) -> None:
        # Create tables if they do not exist.
        statements = [
            "CREATE NODE TABLE IF NOT EXISTS Concept(id STRING, title STRING, keywords STRING, level STRING DEFAULT 'B1', PRIMARY KEY(id))",
            "CREATE NODE TABLE IF NOT EXISTS User(id STRING, PRIMARY KEY(id))",
            "CREATE REL TABLE IF NOT EXISTS Edge(FROM Concept TO Concept, relation STRING)",
            "CREATE REL TABLE IF NOT EXISTS Mastery(FROM User TO Concept, score DOUBLE)",
        ]
        for stmt in statements:
            try:
                self._conn.execute(stmt)
            except Exception:
                # Ignore schema creation errors if already exists
                continue
        # Add level column to existing Concept table if it was created without it
        try:
            self._conn.execute("ALTER TABLE Concept ADD level STRING DEFAULT 'B1'")
        except Exception:
            pass  # column already exists

    def _seed_default_graph(self) -> None:
        """
        Seed comprehensive curriculum concepts for English learning.
        
        Structure:
        - Grammar concepts (A1 → C2)
        - Vocabulary domains
        - Pronunciation patterns
        - Common error patterns for Vietnamese learners
        """
        nodes: Dict[str, Dict[str, str]] = {
            # ============================================
            # GRAMMAR - Level A1 (Beginner)
            # ============================================
            "concept:grammar.subject_verb_agreement": {
                "title": "Subject-verb agreement",
                "keywords": "subject verb agreement I you we they base verb goes go",
                "level": "A1",
            },
            "concept:grammar.third_person_s": {
                "title": "Third-person -s",
                "keywords": "third person he she it adds s",
                "level": "A1",
            },
            "concept:grammar.present_simple": {
                "title": "Present Simple",
                "keywords": "present simple routines habits every day always usually",
                "level": "A1",
            },
            "concept:grammar.articles_a_an": {
                "title": "Articles a/an",
                "keywords": "article a an indefinite countable singular noun",
                "level": "A1",
            },
            "concept:grammar.to_be": {
                "title": "Verb to be",
                "keywords": "am is are was were be being been",
                "level": "A1",
            },
            "concept:grammar.plural_nouns": {
                "title": "Plural nouns",
                "keywords": "plural s es ies irregular plurals",
                "level": "A1",
            },
            "concept:grammar.questions_yes_no": {
                "title": "Yes/No Questions",
                "keywords": "question do does is are did yes no short answer form",
                "level": "A1",
            },
            "concept:grammar.question_words": {
                "title": "Question Words (Wh-)",
                "keywords": "what where when who why how question wh information",
                "level": "A1",
            },
            "concept:grammar.imperatives": {
                "title": "Imperatives",
                "keywords": "imperative command request go sit stop don't please open close",
                "level": "A1",
            },
            "concept:grammar.demonstratives": {
                "title": "Demonstratives",
                "keywords": "demonstrative this that these those near far singular plural",
                "level": "A1",
            },
            "concept:grammar.there_is_are": {
                "title": "There is / There are",
                "keywords": "there is are was were existence location some any",
                "level": "A1",
            },
            "concept:error.missing_auxiliary": {
                "title": "Missing Auxiliary (do/does/did)",
                "keywords": "missing auxiliary do does did question negative you like he like",
                "level": "A1",
            },

            # ============================================
            # GRAMMAR - Level A2 (Elementary)
            # ============================================
            "concept:grammar.past_simple": {
                "title": "Past Simple",
                "keywords": "past simple ed yesterday last ago regular irregular",
                "level": "A2",
            },
            "concept:grammar.past_time_markers": {
                "title": "Past time markers",
                "keywords": "yesterday last ago past time markers week month",
                "level": "A2",
            },
            "concept:grammar.future_will": {
                "title": "Future with will",
                "keywords": "will future prediction promise tomorrow next",
                "level": "A2",
            },
            "concept:grammar.going_to": {
                "title": "Going to for plans",
                "keywords": "going to plan intention future arranged",
                "level": "A2",
            },
            "concept:grammar.comparatives": {
                "title": "Comparatives",
                "keywords": "comparative er more than bigger better worse",
                "level": "A2",
            },
            "concept:grammar.superlatives": {
                "title": "Superlatives",
                "keywords": "superlative est most the biggest best worst",
                "level": "A2",
            },
            "concept:grammar.adverbs_frequency": {
                "title": "Adverbs of Frequency",
                "keywords": "always usually often sometimes rarely never frequency adverb hardly ever",
                "level": "A2",
            },
            "concept:grammar.countable_uncountable": {
                "title": "Countable & Uncountable Nouns",
                "keywords": "countable uncountable noun water rice some any much many few little piece of",
                "level": "A2",
            },
            "concept:grammar.possessive_s": {
                "title": "Possessive 's",
                "keywords": "possessive s apostrophe mine yours his hers its our their belong",
                "level": "A2",
            },
            "concept:error.preposition_confusion": {
                "title": "Preposition Confusion",
                "keywords": "wrong preposition at in on for to from with about by during Vietnamese",
                "level": "A2",
            },
            "concept:error.overuse_very": {
                "title": "Overuse of 'Very'",
                "keywords": "overuse very extremely incredibly absolutely terribly awfully stronger adjective",
                "level": "A2",
            },
            "concept:error.word_order_svo": {
                "title": "Word Order (SVO) Error",
                "keywords": "word order SVO Vietnamese influence adverb before verb subject position",
                "level": "A2",
            },
            "concept:vocab.emotions_feelings": {
                "title": "Emotions & Feelings",
                "keywords": "happy sad angry excited nervous scared worried proud embarrassed surprised lonely bored",
                "level": "A1",
            },
            "concept:vocab.body_parts": {
                "title": "Body Parts",
                "keywords": "head face eyes ears nose mouth neck shoulder arm hand finger back leg knee foot",
                "level": "A1",
            },
            "concept:vocab.transport": {
                "title": "Transport & Commuting",
                "keywords": "bus train car bike taxi plane subway metro ticket station platform commute",
                "level": "A2",
            },
            "concept:vocab.home_housing": {
                "title": "Home & Housing",
                "keywords": "house flat apartment room kitchen bedroom bathroom living room furniture rent buy",
                "level": "A2",
            },
            "concept:conversation.expressing_feelings": {
                "title": "Expressing Feelings",
                "keywords": "feeling emotion express happy sad angry nervous afraid tell how feel",
                "level": "A1",
            },

            # ============================================
            # GRAMMAR - Level B1 (Intermediate)
            # ============================================
            "concept:grammar.present_perfect": {
                "title": "Present Perfect",
                "keywords": "present perfect have has ed experience ever never since for",
                "level": "B1",
            },
            "concept:grammar.present_continuous": {
                "title": "Present Continuous",
                "keywords": "present continuous progressive ing now currently at the moment",
                "level": "B1",
            },
            "concept:grammar.conditionals_first": {
                "title": "First Conditional",
                "keywords": "if will first conditional real possible future",
                "level": "B1",
            },
            "concept:grammar.modal_can_could": {
                "title": "Modal: can/could",
                "keywords": "can could ability permission possibility request",
                "level": "B1",
            },
            "concept:grammar.modal_must_should": {
                "title": "Modal: must/should",
                "keywords": "must should obligation advice necessity recommendation",
                "level": "B1",
            },
            "concept:grammar.passive_voice": {
                "title": "Passive Voice",
                "keywords": "passive voice be done was made is being by agent",
                "level": "B1",
            },
            "concept:grammar.present_perfect_continuous": {
                "title": "Present Perfect Continuous",
                "keywords": "present perfect continuous have been doing since for how long tired dirty",
                "level": "B1",
            },
            "concept:grammar.phrasal_verbs_common": {
                "title": "Common Phrasal Verbs",
                "keywords": "phrasal verb look up give up turn on pick up put off run out figure out come across break down",
                "level": "B1",
            },
            "concept:error.make_do_confusion": {
                "title": "Make vs Do Confusion",
                "keywords": "make do confusion make a decision do homework make friends do exercise",
                "level": "B1",
            },
            "concept:error.tell_say_confusion": {
                "title": "Tell vs Say Confusion",
                "keywords": "tell say confusion tell me said to me told said that report",
                "level": "B1",
            },
            "concept:vocab.personality_traits": {
                "title": "Personality & Character",
                "keywords": "personality kind friendly shy confident brave honest patient creative ambitious generous stubborn",
                "level": "B1",
            },
            "concept:vocab.social_media": {
                "title": "Social Media & Internet",
                "keywords": "social media post share like follow comment hashtag profile feed story viral trending influencer",
                "level": "B1",
            },
            "concept:conversation.telephone_email": {
                "title": "Telephone & Email",
                "keywords": "phone call email message send reply forward subject dear regards hold speak",
                "level": "B1",
            },
            "concept:conversation.complaint_feedback": {
                "title": "Complaint & Feedback",
                "keywords": "complain complaint feedback problem issue unhappy disappointed refund exchange",
                "level": "B1",
            },

            # ============================================
            # GRAMMAR - Level B2 (Upper-Intermediate)
            # ============================================
            "concept:grammar.past_perfect": {
                "title": "Past Perfect",
                "keywords": "past perfect had done before after earlier",
                "level": "B2",
            },
            "concept:grammar.conditionals_second": {
                "title": "Second Conditional",
                "keywords": "if would second conditional unreal hypothetical imagine",
                "level": "B2",
            },
            "concept:grammar.conditionals_third": {
                "title": "Third Conditional",
                "keywords": "if would have third conditional past unreal regret",
                "level": "B2",
            },
            "concept:grammar.relative_clauses": {
                "title": "Relative Clauses",
                "keywords": "relative clause who which that whose whom defining non-defining",
                "level": "B2",
            },
            "concept:grammar.reported_speech": {
                "title": "Reported Speech",
                "keywords": "reported speech indirect said told asked that would",
                "level": "B2",
            },
            "concept:grammar.wish_regret": {
                "title": "Wish & Regret Structures",
                "keywords": "wish regret if only I wish had done would rather had better could have should have",
                "level": "B2",
            },
            "concept:grammar.noun_clauses": {
                "title": "Noun Clauses",
                "keywords": "noun clause that what where how whether I think believe know say",
                "level": "B2",
            },
            "concept:vocab.culture_customs": {
                "title": "Culture & Customs",
                "keywords": "culture tradition custom festival celebration ceremony ritual etiquette manners diverse heritage",
                "level": "B2",
            },
            "concept:conversation.job_interview": {
                "title": "Job Interview",
                "keywords": "job interview cv resume experience skill strength weakness salary position apply",
                "level": "B2",
            },

            # ============================================
            # GRAMMAR - Level C1 (Advanced)
            # ============================================
            "concept:grammar.inversion": {
                "title": "Inversion",
                "keywords": "inversion never rarely seldom hardly scarcely not only",
                "level": "C1",
            },
            "concept:grammar.cleft_sentences": {
                "title": "Cleft Sentences",
                "keywords": "cleft it is what who emphasis focus",
                "level": "C1",
            },
            "concept:grammar.mixed_conditionals": {
                "title": "Mixed Conditionals",
                "keywords": "mixed conditional past present result cause",
                "level": "C1",
            },
            "concept:grammar.ellipsis_substitution": {
                "title": "Ellipsis & Substitution",
                "keywords": "ellipsis substitution so do I neither can she omission avoid repetition cohesion",
                "level": "C1",
            },
            "concept:grammar.subjunctive": {
                "title": "Subjunctive Mood",
                "keywords": "subjunctive mood suggest recommend if I were essential necessary that he go formal",
                "level": "C1",
            },
            "concept:vocab.formal_register": {
                "title": "Formal Register & Academic Style",
                "keywords": "formal register academic style therefore thus hence regarding henceforth hereby aforementioned",
                "level": "C1",
            },

            # ============================================
            # GRAMMAR - Level C2 (Proficiency)
            # ============================================
            "concept:grammar.hedging": {
                "title": "Hedging Language",
                "keywords": "hedging seems appears likely probably tends to apparently arguably possibly may well",
                "level": "C2",
            },
            "concept:grammar.discourse_cohesion": {
                "title": "Discourse Markers & Cohesion",
                "keywords": "furthermore nevertheless however in contrast on the other hand accordingly consequently nonetheless",
                "level": "C2",
            },

            # ============================================
            # VOCABULARY DOMAINS
            # ============================================
            "concept:vocab.daily_life": {
                "title": "Daily Life Vocabulary",
                "keywords": "daily routine morning evening food home family",
                "level": "A1",
            },
            "concept:vocab.work_business": {
                "title": "Work & Business",
                "keywords": "work office meeting business job career professional",
                "level": "B1",
            },
            "concept:vocab.academic": {
                "title": "Academic Vocabulary",
                "keywords": "academic research study analyze evaluate evidence",
                "level": "B2",
            },
            
            # ============================================
            # COMMON ERRORS (Vietnamese Learners)
            # ============================================
            "concept:error.article_omission": {
                "title": "Article Omission",
                "keywords": "missing article the a an Vietnamese learner",
                "level": "A1",
            },
            "concept:error.tense_confusion": {
                "title": "Tense Confusion",
                "keywords": "wrong tense past present future confused",
                "level": "A2",
            },
            "concept:error.subject_pronoun_drop": {
                "title": "Subject Pronoun Drop",
                "keywords": "missing subject pronoun I he she it",
                "level": "A1",
            },
            "concept:error.wrong_tense_reported": {
                "title": "Wrong Tense in Reported Speech",
                "keywords": "reported speech tense shift past present said told would could had",
                "level": "B1",
            },
            "concept:error.gerund_after_preposition": {
                "title": "Gerund After Preposition",
                "keywords": "gerund after preposition at by in of about interested in good at",
                "level": "B1",
            },

            # ============================================
            # QA / MULTI-HOP BRIDGE CONCEPTS
            # ============================================
            "concept:qa.person_nationality": {
                "title": "Person and Nationality",
                "keywords": "person nationality born citizen country same nationality",
                "level": "B1",
            },
            "concept:qa.person_profession": {
                "title": "Person and Profession",
                "keywords": "person profession occupation manager actor singer director",
                "level": "B1",
            },
            "concept:qa.film_director": {
                "title": "Film and Director",
                "keywords": "film movie directed by director",
                "level": "B1",
            },
            "concept:qa.album_release": {
                "title": "Album Release",
                "keywords": "album release released year music track",
                "level": "B1",
            },
            "concept:qa.book_author": {
                "title": "Book and Author",
                "keywords": "book novel author wrote written",
                "level": "B1",
            },
            "concept:qa.location_country": {
                "title": "Location and Country",
                "keywords": "location city country in located where",
                "level": "A2",
            },
            "concept:qa.location_region": {
                "title": "Location and Region",
                "keywords": "region state province county district",
                "level": "A2",
            },
            "concept:qa.organization_founder": {
                "title": "Organization and Founder",
                "keywords": "organization founded founder company institute",
                "level": "B2",
            },
            "concept:qa.organization_headquarters": {
                "title": "Organization Headquarters",
                "keywords": "organization headquarters based in office",
                "level": "B1",
            },
            "concept:qa.sports_team_league": {
                "title": "Sports Team and League",
                "keywords": "team league club football basketball",
                "level": "B1",
            },
            "concept:qa.time_event": {
                "title": "Time and Event",
                "keywords": "when year date founded released born",
                "level": "A2",
            },
            "concept:qa.bridge_comparison": {
                "title": "Bridge Comparison",
                "keywords": "both same compare comparison relation",
                "level": "B2",
            },
        }

        # Edge format: from -> [(to, relation)]
        edges: Dict[str, List[Tuple[str, str]]] = {
            # A1 → A2 prerequisites
            "concept:grammar.present_simple": [
                ("concept:grammar.past_simple", "prerequisite_of"),
                ("concept:grammar.present_continuous", "prerequisite_of"),
            ],
            "concept:grammar.to_be": [
                ("concept:grammar.present_continuous", "prerequisite_of"),
                ("concept:grammar.passive_voice", "prerequisite_of"),
            ],
            "concept:grammar.subject_verb_agreement": [
                ("concept:grammar.third_person_s", "related_to"),
                ("concept:grammar.present_simple", "related_to"),
            ],
            
            # A2 → B1 prerequisites
            "concept:grammar.past_simple": [
                ("concept:grammar.present_perfect", "prerequisite_of"),
                ("concept:grammar.past_perfect", "prerequisite_of"),
            ],
            "concept:grammar.future_will": [
                ("concept:grammar.conditionals_first", "prerequisite_of"),
            ],
            
            # B1 → B2 prerequisites
            "concept:grammar.conditionals_first": [
                ("concept:grammar.conditionals_second", "prerequisite_of"),
            ],
            "concept:grammar.conditionals_second": [
                ("concept:grammar.conditionals_third", "prerequisite_of"),
                ("concept:grammar.mixed_conditionals", "prerequisite_of"),
            ],
            "concept:grammar.present_perfect": [
                ("concept:grammar.past_perfect", "prerequisite_of"),
            ],
            
            # Related concepts
            "concept:grammar.comparatives": [
                ("concept:grammar.superlatives", "related_to"),
            ],
            "concept:grammar.articles_a_an": [
                ("concept:error.article_omission", "related_to"),
            ],
            "concept:grammar.past_time_markers": [
                ("concept:error.tense_confusion", "related_to"),
            ],
            "concept:qa.person_profession": [
                ("concept:qa.film_director", "related_to"),
                ("concept:qa.organization_founder", "related_to"),
            ],
            "concept:qa.film_director": [
                ("concept:qa.person_nationality", "bridge_to"),
                ("concept:qa.time_event", "related_to"),
            ],
            "concept:qa.album_release": [
                ("concept:qa.time_event", "related_to"),
                ("concept:qa.person_profession", "related_to"),
            ],
            "concept:qa.book_author": [
                ("concept:qa.person_profession", "related_to"),
                ("concept:qa.bridge_comparison", "bridge_to"),
            ],
            "concept:qa.location_region": [
                ("concept:qa.location_country", "prerequisite_of"),
            ],
            "concept:qa.organization_founder": [
                ("concept:qa.organization_headquarters", "related_to"),
                ("concept:qa.location_country", "bridge_to"),
            ],
            "concept:qa.sports_team_league": [
                ("concept:qa.location_country", "related_to"),
                ("concept:qa.bridge_comparison", "bridge_to"),
            ],
            "concept:qa.time_event": [
                ("concept:qa.bridge_comparison", "related_to"),
            ],

            # ── New A1 grammar edges ──────────────────────────────────
            "concept:grammar.to_be": [
                ("concept:grammar.questions_yes_no", "prerequisite_of"),
                ("concept:grammar.there_is_are", "prerequisite_of"),
                ("concept:grammar.demonstratives", "related_to"),
            ],
            "concept:grammar.questions_yes_no": [
                ("concept:grammar.question_words", "related_to"),
                ("concept:error.missing_auxiliary", "related_to"),
            ],
            "concept:grammar.question_words": [
                ("concept:grammar.present_simple", "related_to"),
                ("concept:grammar.to_be", "related_to"),
            ],
            "concept:grammar.plural_nouns": [
                ("concept:grammar.countable_uncountable", "prerequisite_of"),
                ("concept:grammar.demonstratives", "related_to"),
            ],
            "concept:error.missing_auxiliary": [
                ("concept:grammar.questions_yes_no", "related_to"),
            ],

            # ── New A2 grammar edges ──────────────────────────────────
            "concept:grammar.adverbs_frequency": [
                ("concept:grammar.present_simple", "related_to"),
            ],
            "concept:grammar.countable_uncountable": [
                ("concept:error.article_omission", "related_to"),
            ],
            "concept:grammar.possessive_s": [
                ("concept:grammar.plural_nouns", "related_to"),
                ("concept:vocab.daily_life", "related_to"),
            ],
            "concept:error.preposition_confusion": [
                ("concept:grammar.prepositions_time", "related_to"),
                ("concept:grammar.prepositions_place", "related_to"),
            ],
            "concept:error.word_order_svo": [
                ("concept:grammar.word_order", "related_to"),
                ("concept:grammar.present_simple", "related_to"),
                ("concept:grammar.adverbs_frequency", "related_to"),
            ],

            # ── New B1 grammar edges ──────────────────────────────────
            "concept:grammar.present_perfect_continuous": [
                ("concept:grammar.present_perfect", "related_to"),
                ("concept:grammar.present_continuous", "related_to"),
            ],
            "concept:grammar.phrasal_verbs_common": [
                ("concept:grammar.gerund_infinitive", "related_to"),
                ("concept:vocab.daily_life", "related_to"),
            ],
            "concept:error.make_do_confusion": [
                ("concept:grammar.phrasal_verbs_common", "related_to"),
            ],
            "concept:error.tell_say_confusion": [
                ("concept:grammar.reported_speech", "related_to"),
            ],
            "concept:error.gerund_after_preposition": [
                ("concept:grammar.gerund_infinitive", "related_to"),
            ],
            "concept:error.wrong_tense_reported": [
                ("concept:grammar.reported_speech", "related_to"),
                ("concept:error.tense_confusion", "related_to"),
            ],

            # ── New B2 grammar edges ──────────────────────────────────
            "concept:grammar.wish_regret": [
                ("concept:grammar.conditionals_second", "related_to"),
                ("concept:grammar.conditionals_third", "related_to"),
            ],
            "concept:grammar.noun_clauses": [
                ("concept:grammar.relative_clauses", "related_to"),
                ("concept:grammar.reported_speech", "related_to"),
            ],

            # ── New C1 grammar edges ──────────────────────────────────
            "concept:grammar.ellipsis_substitution": [
                ("concept:grammar.inversion", "related_to"),
            ],
            "concept:grammar.subjunctive": [
                ("concept:grammar.conditionals_second", "related_to"),
                ("concept:grammar.modal_must_should", "related_to"),
            ],

            # ── New C2 grammar edges ──────────────────────────────────
            "concept:grammar.hedging": [
                ("concept:grammar.modal_can_could", "related_to"),
                ("concept:vocab.formal_register", "related_to"),
            ],
            "concept:grammar.discourse_cohesion": [
                ("concept:grammar.conjunctions", "related_to"),
                ("concept:vocab.formal_register", "related_to"),
            ],

            # ── New vocab edges ───────────────────────────────────────
            "concept:vocab.emotions_feelings": [
                ("concept:conversation.expressing_feelings", "related_to"),
                ("concept:vocab.daily_life", "related_to"),
            ],
            "concept:vocab.body_parts": [
                ("concept:vocab.health", "related_to"),
            ],
            "concept:vocab.transport": [
                ("concept:vocab.travel", "related_to"),
                ("concept:vocab.daily_life", "related_to"),
            ],
            "concept:vocab.home_housing": [
                ("concept:vocab.daily_life", "related_to"),
            ],
            "concept:vocab.personality_traits": [
                ("concept:conversation.job_interview", "related_to"),
                ("concept:conversation.small_talk", "related_to"),
            ],
            "concept:vocab.social_media": [
                ("concept:vocab.technology", "related_to"),
            ],
            "concept:vocab.culture_customs": [
                ("concept:vocab.daily_life", "related_to"),
            ],
            "concept:vocab.formal_register": [
                ("concept:vocab.academic", "related_to"),
                ("concept:vocab.work_business", "related_to"),
            ],

            # ── New conversation edges ────────────────────────────────
            "concept:conversation.expressing_feelings": [
                ("concept:vocab.emotions_feelings", "related_to"),
                ("concept:conversation.small_talk", "related_to"),
            ],
            "concept:conversation.telephone_email": [
                ("concept:conversation.making_appointments", "related_to"),
                ("concept:vocab.work_business", "related_to"),
            ],
            "concept:conversation.job_interview": [
                ("concept:vocab.work_business", "related_to"),
                ("concept:vocab.personality_traits", "related_to"),
            ],
            "concept:conversation.complaint_feedback": [
                ("concept:vocab.shopping", "related_to"),
                ("concept:conversation.expressing_opinions", "related_to"),
            ],
        }

        # Insert nodes (with level)
        for node_id, meta in nodes.items():
            title = meta.get("title", "")
            keywords = meta.get("keywords", "")
            level = meta.get("level", "B1")
            try:
                self._conn.execute(
                    "MERGE (c:Concept {id: $id}) "
                    "ON CREATE SET c.title = $title, c.keywords = $keywords, c.level = $level "
                    "ON MATCH SET c.title = $title, c.keywords = $keywords, c.level = $level",
                    {"id": node_id, "title": title, "keywords": keywords, "level": level},
                )
            except Exception:
                continue

        # Insert edges
        for from_id, rels in edges.items():
            for to_id, relation in rels:
                try:
                    self._conn.execute(
                        "MATCH (a:Concept), (b:Concept) WHERE a.id = $from AND b.id = $to "
                        "MERGE (a)-[:Edge {relation: $relation}]->(b)",
                        {"from": from_id, "to": to_id, "relation": relation},
                    )
                except Exception:
                    continue

    def _extended_knowledge_path(self) -> str:
        configured = os.getenv("KG_EXTENDED_KNOWLEDGE_PATH", "").strip()
        if configured:
            return os.path.abspath(configured)
        default_path = os.path.join(os.path.dirname(__file__), "..", "..", "data", "knowledge_extended.json")
        return os.path.abspath(default_path)

    def _kg_data_dir(self) -> str:
        """Return path to the domain-specific KG data directory (data/kg/)."""
        return os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "data", "kg")
        )

    def _sync_external_knowledge(self) -> None:
        """Load all knowledge JSON files into KuzuDB (non-destructive MERGE).

        Sources (in order):
        1. data/knowledge_extended.json  — legacy single-file, for backward compat
        2. data/kg/*.json                 — domain-specific files, one per topic area
        """
        payloads: List[tuple[str, dict]] = []

        # Source 1: legacy single file
        legacy = self._extended_knowledge_path()
        if os.path.isfile(legacy):
            try:
                with open(legacy, "r", encoding="utf-8") as f:
                    payloads.append((legacy, json.load(f)))
            except Exception as exc:
                logger.warning("[KG] Failed loading %s: %s", legacy, exc)

        # Source 2: domain directory
        kg_dir = self._kg_data_dir()
        if os.path.isdir(kg_dir):
            for fname in sorted(os.listdir(kg_dir)):
                if not fname.endswith(".json"):
                    continue
                fpath = os.path.join(kg_dir, fname)
                try:
                    with open(fpath, "r", encoding="utf-8") as f:
                        payloads.append((fpath, json.load(f)))
                except Exception as exc:
                    logger.warning("[KG] Failed loading %s: %s", fpath, exc)

        total_concepts = 0
        total_edges = 0

        for path, payload in payloads:
            if not isinstance(payload, dict):
                continue
            concepts = payload.get("concepts")
            edges = payload.get("edges")
            if not isinstance(concepts, list):
                continue

            ins_c = 0
            ins_e = 0

            for concept in concepts:
                if not isinstance(concept, dict):
                    continue
                node_id = str(concept.get("id") or "").strip()
                if not node_id:
                    continue
                title = str(concept.get("title") or node_id).strip()
                keywords = str(concept.get("keywords") or "").strip()
                level = str(concept.get("level") or "B1").strip() or "B1"
                try:
                    self._conn.execute(
                        "MERGE (c:Concept {id: $id}) "
                        "ON CREATE SET c.title = $title, c.keywords = $keywords, c.level = $level "
                        "ON MATCH SET c.title = $title, c.keywords = $keywords, c.level = $level",
                        {"id": node_id, "title": title, "keywords": keywords, "level": level},
                    )
                    ins_c += 1
                except Exception:
                    continue

            if isinstance(edges, list):
                for edge in edges:
                    if not isinstance(edge, dict):
                        continue
                    from_id = str(edge.get("from") or "").strip()
                    to_id = str(edge.get("to") or "").strip()
                    relation = str(edge.get("relation") or "related_to").strip() or "related_to"
                    if not from_id or not to_id:
                        continue
                    try:
                        self._conn.execute(
                            "MATCH (a:Concept), (b:Concept) WHERE a.id = $from AND b.id = $to "
                            "MERGE (a)-[:Edge {relation: $relation}]->(b)",
                            {"from": from_id, "to": to_id, "relation": relation},
                        )
                        ins_e += 1
                    except Exception:
                        continue

            if ins_c or ins_e:
                logger.info(
                    "[KG] Synced %s: concepts=%d edges=%d",
                    os.path.basename(path), ins_c, ins_e,
                )
            total_concepts += ins_c
            total_edges += ins_e

        if total_concepts or total_edges:
            logger.info("[KG] Total synced: concepts=%d edges=%d", total_concepts, total_edges)

    def get_concepts(self) -> Dict[str, Dict[str, str]]:
        # Return warm in-memory cache if available (Phase 1 optimisation).
        if self._concepts_cache is not None:
            return self._concepts_cache

        concepts: Dict[str, Dict[str, str]] = {}
        try:
            result = self._conn.execute("MATCH (c:Concept) RETURN c.id, c.title, c.keywords, c.level")
            while result.has_next():  # type: ignore[union-attr]
                row: list = result.get_next()  # type: ignore[union-attr]
                concepts[row[0]] = {
                    "title": row[1],
                    "keywords": row[2] or "",
                    "level": row[3] or "B1",
                }
        except Exception as exc:
            if self._is_corruption_error(exc) and self._recover_and_retry("get_concepts"):
                return self.get_concepts()
            return concepts
        return concepts

    # ── Phase 1: In-Memory Concept Cache + Inverted Keyword Index ─────────────

    def _build_concept_cache(self) -> None:
        """Query KuzuDB once, populate _concepts_cache + _keyword_index + TF-IDF."""
        cache: Dict[str, Dict[str, str]] = {}
        keyword_index: Dict[str, List[str]] = {}
        try:
            result = self._conn.execute(
                "MATCH (c:Concept) RETURN c.id, c.title, c.keywords, c.level"
            )
            while result.has_next():  # type: ignore[union-attr]
                row: list = result.get_next()  # type: ignore[union-attr]
                cid: str = row[0]
                title: str = row[1] or ""
                keywords: str = row[2] or ""
                level: str = row[3] or "B1"
                cache[cid] = {"title": title, "keywords": keywords, "level": level}
                # Build inverted keyword index
                for tok in re.findall(r"[a-z0-9_']+", (f"{title} {keywords}").lower()):
                    if len(tok) >= 3:
                        keyword_index.setdefault(tok, []).append(cid)
        except Exception as exc:
            logger.warning("[KG] _build_concept_cache failed: %s", exc)
            return

        self._concepts_cache = cache
        self._keyword_index = keyword_index
        logger.info(
            "[KG] Concept cache warmed: %d concepts, %d index keys",
            len(cache), len(keyword_index),
        )
        self._build_tfidf_index()

    def _invalidate_concept_cache(self) -> None:
        """Clear concept cache so next get_concepts() rebuilds from KuzuDB."""
        self._concepts_cache = None
        self._keyword_index = {}
        self._tfidf_concept_ids = []
        self._tfidf_idf = {}
        self._tfidf_vectors = []

    def get_seed_concepts_fast(self, text: str) -> List[str]:
        """O(words_in_text) concept seeding via inverted keyword index.

        Replaces the O(n_concepts × n_keywords) loop in kg_expand_node Phase 1.
        """
        if not self._keyword_index:
            return []
        tokens = re.findall(r"[a-z0-9_']+", text.lower())
        seen: set = set()
        seeds: List[str] = []
        for tok in tokens:
            if len(tok) < 3:
                continue
            for cid in self._keyword_index.get(tok, []):
                if cid not in seen:
                    seen.add(cid)
                    seeds.append(cid)
        return seeds

    # ── Phase 3: Pure-Python TF-IDF Semantic Matching ─────────────────────────

    def _build_tfidf_index(self) -> None:
        """Build a lightweight TF-IDF index over concept keyword strings.

        Uses pure Python (no sklearn) — fast enough for ~150 concept documents.
        """
        import math

        if not self._concepts_cache:
            return

        concept_ids = list(self._concepts_cache.keys())
        corpus: List[str] = [
            f"{self._concepts_cache[cid]['title']} {self._concepts_cache[cid]['keywords']}"
            for cid in concept_ids
        ]

        # Tokenise each document
        tokenised: List[List[str]] = [
            [tok for tok in re.findall(r"[a-z0-9_']+", doc.lower()) if len(tok) >= 3]
            for doc in corpus
        ]

        N = len(tokenised)
        if N == 0:
            return

        # Document frequency per term
        df: Dict[str, int] = {}
        for tokens in tokenised:
            for tok in set(tokens):
                df[tok] = df.get(tok, 0) + 1

        # IDF with smoothing
        idf: Dict[str, float] = {
            tok: math.log((N + 1) / (cnt + 1)) + 1.0
            for tok, cnt in df.items()
        }

        # TF-IDF vectors (normalised)
        vectors: List[Dict[str, float]] = []
        for tokens in tokenised:
            if not tokens:
                vectors.append({})
                continue
            tf: Dict[str, float] = {}
            for tok in tokens:
                tf[tok] = tf.get(tok, 0) + 1.0
            total = len(tokens)
            vec: Dict[str, float] = {}
            norm = 0.0
            for tok, cnt in tf.items():
                v = (cnt / total) * idf.get(tok, 1.0)
                vec[tok] = v
                norm += v * v
            if norm > 0:
                sqrt_norm = norm ** 0.5
                vec = {t: v / sqrt_norm for t, v in vec.items()}
            vectors.append(vec)

        self._tfidf_concept_ids = concept_ids
        self._tfidf_idf = idf
        self._tfidf_vectors = vectors
        logger.info("[KG] TF-IDF index built: %d concepts, %d unique terms", N, len(idf))

    def semantic_seed_concepts(self, text: str, top_k: int = 5) -> List[str]:
        """Return top-K concept IDs by TF-IDF cosine similarity to *text*.

        Complements get_seed_concepts_fast() by catching semantic matches that
        exact keyword matching misses (e.g. 'struggling' → 'error_*' concepts).
        """
        import math

        if not self._tfidf_vectors or not self._tfidf_idf:
            return []

        tokens = [tok for tok in re.findall(r"[a-z0-9_']+", text.lower()) if len(tok) >= 3]
        if not tokens:
            return []

        # Build query vector
        tf: Dict[str, float] = {}
        for tok in tokens:
            tf[tok] = tf.get(tok, 0) + 1.0
        total = len(tokens)
        query_vec: Dict[str, float] = {}
        norm = 0.0
        for tok, cnt in tf.items():
            if tok in self._tfidf_idf:
                v = (cnt / total) * self._tfidf_idf[tok]
                query_vec[tok] = v
                norm += v * v
        if norm == 0:
            return []
        sqrt_norm = norm ** 0.5
        query_vec = {t: v / sqrt_norm for t, v in query_vec.items()}

        # Cosine similarity (dot product of pre-normalised vectors)
        scores: List[Tuple[float, str]] = []
        for idx, doc_vec in enumerate(self._tfidf_vectors):
            sim = sum(query_vec.get(t, 0.0) * w for t, w in doc_vec.items())
            if sim > 0.05:
                scores.append((sim, self._tfidf_concept_ids[idx]))

        scores.sort(key=lambda x: x[0], reverse=True)
        return [cid for _, cid in scores[:top_k]]



    async def expand(self, seed_nodes: List[str], hops: int = 1) -> KGHits:
        expanded_nodes: List[KGExpandedNode] = []
        paths: List[KGPath] = []

        if not seed_nodes:
            return KGHits(seed_nodes=[], expanded_nodes=[], paths=[])

        try:
            for seed in seed_nodes:
                result = self._conn.execute(
                    "MATCH (a:Concept)-[e:Edge]->(b:Concept) "
                    "WHERE a.id = $seed RETURN b.id, e.relation, b.level",
                    {"seed": seed},
                )
                while result.has_next():  # type: ignore[union-attr]
                    row: list = result.get_next()  # type: ignore[union-attr]
                    expanded_nodes.append(KGExpandedNode(
                        id=row[0], type=row[1],
                        properties={"relation": row[1], "level": row[2] or "B1"},
                    ))
                    paths.append(KGPath(nodes=[seed, row[0]], edges=[row[1]]))
        except Exception as exc:
            if self._is_corruption_error(exc) and self._recover_and_retry("expand"):
                return await self.expand(seed_nodes=seed_nodes, hops=hops)
            return KGHits(seed_nodes=seed_nodes, expanded_nodes=[], paths=[])

        return KGHits(seed_nodes=seed_nodes, expanded_nodes=expanded_nodes, paths=paths)

    async def expand_best_first(
        self,
        seed_nodes: List[str],
        learner_level: str = "B1",
        max_hops: int = 2,
        max_nodes: int = 10,
    ) -> KGHits:
        """
        Level-aware best-first graph expansion (paper Alg. 4).

        Uses PedWeight priority: concepts at the learner's level get
        highest priority (1.0), ±1 level get 0.7, others 0.3.

        Phase 2 optimisation: results are cached in Redis keyed by
        sha1(sorted(seed_nodes) + learner_level + max_hops + max_nodes)
        with a 30-minute TTL to skip redundant BFS traversals.
        """
        import heapq
        import hashlib
        import json as _json

        if not seed_nodes:
            return KGHits(seed_nodes=[], expanded_nodes=[], paths=[])

        # ── Phase 2: Redis subgraph result cache ──────────────────────────
        _cache_key = (
            "kg:subgraph:"
            + hashlib.sha1(
                f"{sorted(seed_nodes)}:{learner_level}:{max_hops}:{max_nodes}".encode()
            ).hexdigest()
        )
        try:
            from api.core.redis_client import RedisClient
            _redis = await RedisClient.get_instance()
            _cached = await _redis.get(_cache_key)
            if _cached:
                _data = _json.loads(_cached)
                return KGHits(
                    seed_nodes=_data["seeds"],
                    expanded_nodes=[KGExpandedNode(**n) for n in _data["nodes"]],
                    paths=[KGPath(**p) for p in _data["paths"]],
                )
        except Exception:
            _redis = None
        # ─────────────────────────────────────────────────────────────────

        CEFR_ORD = {"A1": 1, "A2": 2, "B1": 3, "B2": 4, "C1": 5, "C2": 6}
        learner_ord = CEFR_ORD.get(learner_level, 3)

        def ped_weight(neighbor_level: str) -> float:
            n_ord = CEFR_ORD.get(neighbor_level, 3)
            diff = abs(n_ord - learner_ord)
            if diff == 0:
                return 1.0
            elif diff == 1:
                return 0.7
            return 0.3

        expanded_nodes: List[KGExpandedNode] = []
        paths: List[KGPath] = []
        visited: set = set(seed_nodes)

        # Priority queue: (-weight, hop_depth, concept_id, parent_id, relation)
        # Negate weight because heapq is a min-heap
        frontier: list = []
        for s in seed_nodes:
            heapq.heappush(frontier, (-1.0, 0, s, None, None))

        try:
            while frontier and len(expanded_nodes) < max_nodes:
                neg_w, depth, cid, parent, rel = heapq.heappop(frontier)

                if depth > 0:  # don't add seeds themselves as expanded
                    expanded_nodes.append(KGExpandedNode(
                        id=cid, type=rel or "related_to",
                        properties={"relation": rel or "related_to", "depth": depth},
                    ))
                    if parent:
                        paths.append(KGPath(nodes=[parent, cid], edges=[rel or "related_to"]))

                if depth >= max_hops:
                    continue

                # Expand neighbors
                result = self._conn.execute(
                    "MATCH (a:Concept)-[e:Edge]->(b:Concept) "
                    "WHERE a.id = $cid RETURN b.id, e.relation, b.level",
                    {"cid": cid},
                )
                while result.has_next():  # type: ignore[union-attr]
                    row = result.get_next()  # type: ignore[union-attr]
                    neighbor_id, edge_rel, neighbor_level = row[0], row[1], row[2] or "B1"
                    if neighbor_id not in visited:
                        visited.add(neighbor_id)
                        w = ped_weight(neighbor_level)
                        heapq.heappush(frontier, (-w, depth + 1, neighbor_id, cid, edge_rel))
        except Exception as e:
            if self._is_corruption_error(e) and self._recover_and_retry("expand_best_first"):
                return await self.expand_best_first(
                    seed_nodes=seed_nodes,
                    learner_level=learner_level,
                    max_hops=max_hops,
                    max_nodes=max_nodes,
                )
            logger.warning(f"[KG] expand_best_first error: {e}")

        hits = KGHits(seed_nodes=seed_nodes, expanded_nodes=expanded_nodes, paths=paths)

        # ── Phase 2: Store result in Redis (TTL 30 min) ───────────────────
        try:
            if _redis is not None:
                _payload = _json.dumps({
                    "seeds": seed_nodes,
                    "nodes": [
                        {"id": n.id, "type": n.type, "properties": n.properties}
                        for n in expanded_nodes
                    ],
                    "paths": [
                        {"nodes": p.nodes, "edges": p.edges}
                        for p in paths
                    ],
                })
                await _redis.setex(_cache_key, 1800, _payload)
        except Exception:
            pass
        # ─────────────────────────────────────────────────────────────────

        return hits



    async def record_interaction(
        self,
        user_id: str,
        session_id: str,
        linked_concepts: List[str],
        error_types: List[str],
    ) -> None:
        if not user_id or not linked_concepts:
            return None

        # Ensure user node exists
        try:
            self._conn.execute(
                "MERGE (u:User {id: $id})",
                {"id": user_id},
            )
        except Exception:
            return None

        for concept_id in linked_concepts:
            # Simple mastery update: decrease on errors, increase otherwise
            delta = -0.05 if error_types else 0.03
            try:
                self._conn.execute(
                    "MATCH (u:User), (c:Concept) "
                    "WHERE u.id = $uid AND c.id = $cid "
                    "MERGE (u)-[m:Mastery]->(c) "
                    "ON CREATE SET m.score = $score "
                    "ON MATCH SET m.score = min(1.0, max(0.0, m.score + $delta))",
                    {"uid": user_id, "cid": concept_id, "score": 0.5, "delta": delta},
                )
            except Exception:
                continue

        return None

    async def get_user_mastery(self, user_id: str) -> Dict[str, float]:
        """
        Get mastery scores for all concepts a user has interacted with.
        
        Returns:
            Dict mapping concept_id -> mastery_score (0.0 to 1.0)
        """
        mastery: Dict[str, float] = {}
        
        if not user_id:
            return mastery
        
        try:
            result = self._conn.execute(
                "MATCH (u:User)-[m:Mastery]->(c:Concept) "
                "WHERE u.id = $uid RETURN c.id, m.score",
                {"uid": user_id},
            )
            while result.has_next():  # type: ignore[union-attr]
                row: list = result.get_next()  # type: ignore[union-attr]
                mastery[row[0]] = row[1]
        except Exception:
            pass
        
        return mastery

    async def get_recommended_concepts(
        self, 
        user_id: str, 
        current_level: str = "B1",
        limit: int = 5
    ) -> List[Dict[str, Any]]:
        """
        Get recommended concepts for a user based on:
        1. Low mastery concepts at current level
        2. Prerequisites of weak concepts
        3. Concepts they haven't seen yet
        
        Returns:
            List of recommended concept dicts with id, title, reason
        """
        recommendations: List[Dict[str, Any]] = []
        level_order = ["A1", "A2", "B1", "B2", "C1", "C2"]
        
        try:
            # Get user's current mastery
            user_mastery = await self.get_user_mastery(user_id)
            
            # Find weak concepts (mastery < 0.6) at current level
            all_concepts = self.get_concepts()
            
            for concept_id, meta in all_concepts.items():
                if len(recommendations) >= limit:
                    break
                    
                # Check if this is a concept at appropriate level
                # (Keywords don't have level stored yet, so check all)
                mastery_score = user_mastery.get(concept_id, 0.5)
                
                if mastery_score < 0.6:
                    recommendations.append({
                        "id": concept_id,
                        "title": meta.get("title", ""),
                        "mastery": mastery_score,
                        "reason": "Low mastery - needs practice",
                    })
            
            # If not enough recommendations, add unseen concepts
            if len(recommendations) < limit:
                for concept_id, meta in all_concepts.items():
                    if len(recommendations) >= limit:
                        break
                    if concept_id not in user_mastery:
                        recommendations.append({
                            "id": concept_id,
                            "title": meta.get("title", ""),
                            "mastery": 0.5,
                            "reason": "New concept to explore",
                        })
                        
        except Exception:
            pass
        
        return recommendations[:limit]

    async def get_prerequisites(self, concept_id: str) -> List[str]:
        """
        Get prerequisites for a concept (concepts that should be mastered first).
        
        Returns:
            List of prerequisite concept IDs
        """
        prerequisites: List[str] = []
        
        try:
            result = self._conn.execute(
                "MATCH (a:Concept)-[e:Edge]->(b:Concept) "
                "WHERE b.id = $cid AND e.relation = 'prerequisite_of' "
                "RETURN a.id",
                {"cid": concept_id},
            )
            while result.has_next():  # type: ignore[union-attr]
                row: list = result.get_next()  # type: ignore[union-attr]
                prerequisites.append(row[0])
        except Exception:
            pass
        
        return prerequisites

    async def get_next_concepts(self, concept_id: str) -> List[str]:
        """
        Get concepts that this concept is a prerequisite for.
        
        Returns:
            List of concept IDs that build on this concept
        """
        next_concepts: List[str] = []
        
        try:
            result = self._conn.execute(
                "MATCH (a:Concept)-[e:Edge]->(b:Concept) "
                "WHERE a.id = $cid AND e.relation = 'prerequisite_of' "
                "RETURN b.id",
                {"cid": concept_id},
            )
            while result.has_next():  # type: ignore[union-attr]
                row: list = result.get_next()  # type: ignore[union-attr]
                next_concepts.append(row[0])
        except Exception:
            pass
        
        return next_concepts

    def get_concept_count(self) -> int:
        """Get total number of concepts in the graph."""
        try:
            result = self._conn.execute("MATCH (c:Concept) RETURN count(c)")
            if result.has_next():  # type: ignore[union-attr]
                return result.get_next()[0]  # type: ignore[union-attr]
        except Exception:
            pass
        return 0

    def query_concepts(self, query: str, learner_level: str = "B1", top_k: int = 8) -> List[Dict[str, Any]]:
        """Lexical + level-aware top-K concept retrieval for prompt grounding."""
        normalized = str(query or "").strip().lower()
        if not normalized or top_k <= 0:
            return []

        tokens = [tok for tok in re.findall(r"[a-z0-9_]+", normalized) if len(tok) >= 2]
        if not tokens:
            return []

        concepts = self.get_concepts()
        if not concepts:
            return []

        CEFR_ORD = {"A1": 1, "A2": 2, "B1": 3, "B2": 4, "C1": 5, "C2": 6}
        learner_ord = CEFR_ORD.get(str(learner_level or "B1").upper(), 3)

        scored: List[Tuple[float, str, Dict[str, str]]] = []
        token_set = set(tokens)
        for concept_id, meta in concepts.items():
            title = str(meta.get("title") or "")
            keywords = str(meta.get("keywords") or "")
            haystack = f"{title} {keywords}".lower()
            if not haystack:
                continue

            overlap = sum(1 for tok in token_set if tok in haystack)
            if overlap <= 0:
                continue

            level = str(meta.get("level") or "B1").upper()
            diff = abs(CEFR_ORD.get(level, 3) - learner_ord)
            level_boost = 1.0 if diff == 0 else (0.8 if diff == 1 else 0.6)
            score = (overlap / max(len(token_set), 1)) * level_boost
            scored.append((score, concept_id, meta))

        scored.sort(key=lambda item: item[0], reverse=True)
        return [
            {
                "id": concept_id,
                "title": meta.get("title", concept_id),
                "keywords": meta.get("keywords", ""),
                "level": meta.get("level", "B1"),
                "score": round(float(score), 4),
            }
            for score, concept_id, meta in scored[:top_k]
        ]

