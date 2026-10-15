from __future__ import annotations

from typing import Any, Dict, List, Literal, Optional

from pydantic import BaseModel, ConfigDict, Field


class SuspectedError(BaseModel):
    type: str
    span: str


class DiagnosisV3(BaseModel):
    intent: Literal["fix_grammar", "explain_rule", "translate", "practice"] = "fix_grammar"
    skill: Literal["grammar", "vocabulary", "mixed", "fluency"] = "grammar"
    user_problem: str = ""
    suspected_errors: List[SuspectedError] = Field(default_factory=list)
    root_cause_candidates: List[str] = Field(default_factory=list)
    need_vietnamese: bool = False
    confidence: float = 0.5
    next_best_action: Literal["answer", "ask_clarify"] = "answer"


class V3PipelineContext(BaseModel):
    model_config = ConfigDict(extra="allow")

    user_input: str
    session_id: str
    user_id: str
    metadata: Dict[str, Any] = Field(default_factory=dict)


class KGExpandedNode(BaseModel):
    id: str
    type: str
    properties: Dict[str, Any] = Field(default_factory=dict)


class KGPath(BaseModel):
    nodes: List[str] = Field(default_factory=list)
    edges: List[str] = Field(default_factory=list)


class KGHits(BaseModel):
    seed_nodes: List[str] = Field(default_factory=list)
    expanded_nodes: List[KGExpandedNode] = Field(default_factory=list)
    paths: List[KGPath] = Field(default_factory=list)


class VectorHit(BaseModel):
    id: str
    score: float
    snippet: str = ""


class ExamplePair(BaseModel):
    good: str
    bad: str
    why: Optional[str] = None


class RetrievalBundleV3(BaseModel):
    query: str
    vector_hits: List[VectorHit] = Field(default_factory=list)
    kg_hits: KGHits = Field(default_factory=KGHits)
    examples: List[ExamplePair] = Field(default_factory=list)
    # Tier-1 routing: the topics this turn was narrowed to, empty when the
    # turn is not topic-shaped and the corpus-wide path ran instead.
    routed_topics: List[str] = Field(default_factory=list)
    topic_similarity: float = 0.0


class Correction(BaseModel):
    error: str
    correction: str
    type: str


class LinkedConcept(BaseModel):
    id: str
    weight: float = 0.0


class ActionPlanItem(BaseModel):
    action: str
    concept: Optional[str] = None
    count: Optional[int] = None


class CacheMeta(BaseModel):
    hit: bool = False
    key: Optional[str] = None


class TutorResponseMeta(BaseModel):
    path: str = "slow"
    latency_ms: int = 0
    models_used: List[str] = Field(default_factory=list)
    cache: CacheMeta = Field(default_factory=CacheMeta)


class TutorResponseV3(BaseModel):
    model_config = ConfigDict(extra="allow")

    tutor_response: str
    corrections: List[Correction] = Field(default_factory=list)
    linked_concepts: List[LinkedConcept] = Field(default_factory=list)
    action_plan: List[ActionPlanItem] = Field(default_factory=list)
    confidence: float = 0.0
    metadata: TutorResponseMeta
    native_hint: Optional[str] = None
    pronunciation_tip: Optional[str] = None
    diagnosis: Optional[DiagnosisV3] = None
    retrieval: Optional[RetrievalBundleV3] = None
