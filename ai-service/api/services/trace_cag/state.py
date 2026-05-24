"""
TraceCAG State Schema

Defines the typed state for LangGraph StateGraph.
This state flows through all nodes in the TraceCAG pipeline.
"""

from typing import TypedDict, List, Optional, Any, Dict, Annotated
from operator import add


class LearnerProfile(TypedDict, total=False):
    """Learner profile from Redis cache."""
    level: str  # A1, A2, B1, B2, C1, C2
    native_language: str
    common_errors: List[str]
    vocabulary_count: int
    sessions_completed: int


class KGExpandedNode(TypedDict):
    """Expanded node from Knowledge Graph."""
    id: str
    title: str
    relation: str
    keywords: str


class DiagnosisError(TypedDict):
    """Single error detected in diagnosis."""
    span: str
    type: str
    correction: str
    explanation: str


class VectorHit(TypedDict):
    """Vector search result."""
    id: str
    score: float
    content: str


class RetrievalTraceItem(TypedDict, total=False):
    """Ranked retrieval item for benchmark analysis."""
    item_id: str
    title: str
    text: str
    rank: int
    score: float
    is_relevant: bool


class CacheFingerprint(TypedDict, total=False):
    """Fingerprint for PCC-aware cache keying (paper Alg. 1)."""
    query_norm: str          # normalized user input
    intent: str              # diagnosed intent
    level: str               # CEFR level
    root_concepts: List[str] # root-cause concept IDs
    session_turn: int        # turn number within session


class CacheEntry(TypedDict, total=False):
    """Structured cache entry ⟨F, P_c, R, B, σ, t_c⟩ (paper §4.1)."""
    fingerprint: CacheFingerprint
    graph_bucket: str                  # cheap concept-state bucket for L1 lookup
    profile_snapshot: Dict[str, Any]   # P_c: profile at creation time
    response: str                      # R: tutor response text
    evidence_bundle: List[Dict[str, Any]]  # B: KG snippets, examples
    retrieval_trace: List[RetrievalTraceItem]
    execution_plan: Dict[str, Any]     # σ: strategy, difficulty, slot template
    diagnosis_errors: List[Dict[str, Any]]
    overall_score: float
    grammar_score: float
    fluency_score: float
    vocabulary_level: str
    action_plan: List[Dict[str, Any]]
    created_at: float                  # t_c: timestamp (monotonic)
    ttl: int                           # seconds


class BucketVersionRecord(TypedDict, total=False):
    """
    Version tuple for an L1 graph bucket  v_b = ⟨ν_graph, ν_policy, ν_profile, t_refresh⟩
    (paper §5.3, Algorithm 3).

    A bucket is invalidated when any version field drifts from the current
    deployment constants, or when t_refresh exceeds the bucket TTL.
    """
    nu_graph: int     # graph-schema / neighborhood version (bump on KG rebuild)
    nu_policy: int    # policy-template version (bump on prompt/strategy changes)
    nu_profile: int   # profile-state epoch (future: per-user epoch counter)
    t_refresh: float  # monotonic timestamp of last successful write


class TraceCAGState(TypedDict, total=False):
    """
    Central state for TraceCAG pipeline.
    
    This state is passed through all nodes and updated progressively.
    Using total=False allows optional fields.
    """
    # ============================================
    # Input (set at start)
    # ============================================
    user_input: str
    session_id: str
    user_id: Optional[str]
    input_type: str  # "text" or "voice"
    audio_bytes: Optional[bytes]  # Raw audio if voice input
    benchmark_task: Optional[str]
    benchmark_context: Optional[str]
    benchmark_metadata: Optional[Dict[str, Any]]
    
    # ============================================
    # Learner Context (from Redis cache)
    # ============================================
    learner_profile: LearnerProfile
    conversation_history: List[Dict[str, Any]]
    
    # ============================================
    # Knowledge Graph (from KuzuDB)
    # ============================================
    kg_seed_concepts: List[str]  # Initial matched concepts
    kg_expanded_nodes: List[KGExpandedNode]  # Expanded via graph hops
    kg_paths: List[Dict[str, Any]]  # Paths between concepts
    
    # ============================================
    # Diagnosis (grammar/fluency analysis)
    # ============================================
    diagnosis_intent: str  # "correct", "explain", "practice", "ask"
    diagnosis_errors: List[DiagnosisError]
    diagnosis_root_causes: List[str]  # concept IDs
    diagnosis_confidence: float  # 0.0 - 1.0
    
    # ============================================
    # Retrieval (Vector + KG combined)
    # ============================================
    vector_hits: List[VectorHit]
    jit_soft_graph: Optional[str]  # Compact JIT graph prompt payload
    jit_graph_meta: Dict[str, Any]  # Extraction timing/quality metadata
    retrieved_context: str  # Combined context for generation
    retrieval_trace: List[RetrievalTraceItem]
    retrieval_meta: Dict[str, Any]
    
    # ============================================
    # Response Generation
    # ============================================
    tutor_response: str
    vietnamese_hint: Optional[str]
    native_explanation_requested: Optional[bool]
    pronunciation_tip: Optional[str]
    strategy: str  # praise, scaffold, socratic, feedback
    next_action: str  # continue, hint, correct
    action_plan: List[Dict[str, Any]]
    
    # ============================================
    # Scores
    # ============================================
    fluency_score: float
    grammar_score: float
    vocabulary_level: str
    overall_score: float
    
    # ============================================
    # TTS Output
    # ============================================
    tts_audio_bytes: Optional[bytes]
    tts_audio_url: Optional[str]
    
    # ============================================
    # RAPID Cache Control (paper §4.1)
    # ============================================
    cache_fingerprint: Optional[CacheFingerprint]
    cache_decision: str  # "reuse" | "patch" | "full"
    cache_layer: str     # "none" | "L0" | "L1"
    cache_bucket: str    # graph-aware bucket identifier for L1 lookup
    reuse_risk: float    # ρ ∈ [0,1] from Eq. 2
    adaptive_profile: Optional[str]
    adaptive_features: Dict[str, float]
    adaptive_controller: Dict[str, Any]

    # ============================================
    # Metadata
    # ============================================
    # Policy controls (used for benchmarking/experiments)
    cache_policy: str  # "on" | "off"
    retrieval_policy: str  # "full" | "rapid"
    diagnosis_policy: str  # "auto" | "rules"
    generation_policy: str  # "auto" | "extractive" (template is deprecated alias)
    models_used: Annotated[List[str], add]  # Accumulator pattern
    latency_ms: int
    ttft_ms: int
    graph_update: Dict[str, int]
    cache_hit: bool
    path: str  # "fast" or "slow"
    tokens_saved: int  # Estimated LLM tokens saved via cache (0 on slow path)
    error: Optional[str]  # Error message if any


def create_initial_state(
    user_input: str,
    session_id: str,
    user_id: Optional[str] = None,
    input_type: str = "text",
    learner_profile: Optional[Dict[str, Any]] = None,
    *,
    cache_policy: str = "on",
    retrieval_policy: str = "full",
    diagnosis_policy: str = "auto",
    generation_policy: str = "auto",
    benchmark_task: Optional[str] = None,
    benchmark_context: Optional[str] = None,
    benchmark_metadata: Optional[Dict[str, Any]] = None,
) -> TraceCAGState:
    """
    Create initial state for TraceCAG pipeline.
    
    Args:
        user_input: Text from user (or STT transcript)
        session_id: Unique session ID
        user_id: Optional user ID for personalization
        input_type: "text" or "voice"
        learner_profile: Optional pre-loaded profile
        
    Returns:
        Initial TraceCAGState ready for graph execution
    """
    return TraceCAGState(
        # Input
        user_input=user_input,
        session_id=session_id,
        user_id=user_id,
        input_type=input_type,
        audio_bytes=None,
        benchmark_task=benchmark_task,
        benchmark_context=benchmark_context,
        benchmark_metadata=benchmark_metadata or {},
        
        # Context (will be populated by input_node)
        learner_profile=learner_profile or {"level": "B1"},
        conversation_history=[],
        
        # KG (will be populated by kg_expand_node)
        kg_seed_concepts=[],
        kg_expanded_nodes=[],
        kg_paths=[],
        
        # Diagnosis (will be populated by diagnose_node)
        diagnosis_intent="unknown",
        diagnosis_errors=[],
        diagnosis_root_causes=[],
        diagnosis_confidence=1.0,
        
        # Retrieval (will be populated by retrieve_node)
        vector_hits=[],
        jit_soft_graph=None,
        jit_graph_meta={},
        retrieved_context="",
        retrieval_trace=[],
        retrieval_meta={},
        
        # Response (will be populated by generate_node)
        tutor_response="",
        vietnamese_hint=None,
        native_explanation_requested=False,
        pronunciation_tip=None,
        strategy="scaffold",
        next_action="continue",
        action_plan=[],
        
        # Scores
        fluency_score=0.0,
        grammar_score=0.0,
        vocabulary_level="B1",
        overall_score=0.0,
        
        # TTS
        tts_audio_bytes=None,
        tts_audio_url=None,

        # RAPID cache control
        cache_fingerprint=None,
        cache_decision="full",
        cache_layer="none",
        cache_bucket="",
        reuse_risk=1.0,
        adaptive_profile=None,
        adaptive_features={},
        adaptive_controller={},
        
        # Metadata
        cache_policy=cache_policy,
        retrieval_policy=retrieval_policy,
        diagnosis_policy=diagnosis_policy,
        generation_policy=generation_policy,
        models_used=[],
        latency_ms=0,
        ttft_ms=0,
        graph_update={"latency_ms": 0, "nodes_added": 0, "edges_added": 0},
        cache_hit=False,
        path="slow",
        tokens_saved=0,
        error=None,
    )
