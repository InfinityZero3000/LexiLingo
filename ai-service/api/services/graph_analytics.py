"""
Graph Analytics Service for LexiLingo.

Implements:
1. Centrality Analysis - Rank concepts by structural importance
2. Community Detection - Group related concepts together
3. Smart Pruning - Output only necessary information

Based on GraphCAG principles for memory optimization.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from enum import Enum
from functools import lru_cache
from typing import Dict, List, Optional, Set, Tuple

import networkx as nx

from api.services.kg_service_v3 import KnowledgeGraphServiceV3


logger = logging.getLogger(__name__)


class CentralityType(Enum):
    """Types of centrality measures."""
    DEGREE = "degree"           # Nodes with many connections
    BETWEENNESS = "betweenness" # Nodes on many shortest paths (bridges)
    PAGERANK = "pagerank"       # Nodes pointed by important nodes
    CLOSENESS = "closeness"     # Nodes close to all other nodes


@dataclass
class ConceptImportance:
    """Represents a concept with its importance scores."""
    concept_id: str
    title: str
    degree_centrality: float
    betweenness_centrality: float
    pagerank: float
    combined_score: float  # Weighted combination
    community_id: int


@dataclass
class Community:
    """Represents a group of related concepts."""
    community_id: int
    name: str
    concepts: List[str]
    central_concept: str  # Most important node in community
    keywords: List[str]


@dataclass
class AnalyticsResult:
    """Result of graph analytics."""
    top_concepts: List[ConceptImportance]
    communities: List[Community]
    pruned_concepts: List[str]  # Less important, filtered out
    memory_saved_percent: float


class GraphAnalyticsService:
    """
    Graph Analytics for optimizing KG queries.
    
    Uses NetworkX for:
    - Centrality analysis (identify important concepts)
    - Community detection (group related concepts)
    - Smart pruning (filter out noise)
    """
    
    # Weights for combining centrality scores
    CENTRALITY_WEIGHTS = {
        "degree": 0.3,
        "betweenness": 0.3,
        "pagerank": 0.4,
    }
    
    # Cache TTL (recompute analytics every N requests)
    CACHE_SIZE = 128
    
    def __init__(self, kg: KnowledgeGraphServiceV3):
        self.kg = kg
        self._nx_graph: Optional[nx.DiGraph] = None
        self._centrality_cache: Dict[str, float] = {}
        self._community_cache: Dict[str, int] = {}
        self._analytics_computed = False
        
    def _build_networkx_graph(self) -> nx.DiGraph:
        """
        Build NetworkX DiGraph from KuzuDB.
        
        Returns:
            NetworkX directed graph for analytics
        """
        if self._nx_graph is not None:
            return self._nx_graph
            
        G = nx.DiGraph()
        
        # Get all concepts from KG
        concepts = self.kg.get_concepts()
        
        # Add nodes with attributes
        for concept_id, meta in concepts.items():
            G.add_node(
                concept_id,
                title=meta.get("title", ""),
                keywords=meta.get("keywords", ""),
            )
        
        # Get edges by querying KG
        try:
            result = self.kg._conn.execute(
                "MATCH (a:Concept)-[e:Edge]->(b:Concept) "
                "RETURN a.id, b.id, e.relation"
            )
            while result.has_next():
                row = result.get_next()
                from_id, to_id, relation = row
                G.add_edge(from_id, to_id, relation=relation)
        except Exception as e:
            logger.warning(f"Failed to load edges: {e}")
        
        self._nx_graph = G
        logger.info(f"Built NetworkX graph: {G.number_of_nodes()} nodes, {G.number_of_edges()} edges")
        
        return G
    
    def compute_centrality(self, top_k: int = 10) -> Dict[str, ConceptImportance]:
        """
        Compute centrality scores for all concepts.
        
        Combines multiple centrality measures:
        - Degree: Concepts with many connections (foundational)
        - Betweenness: Concepts that bridge different areas
        - PageRank: Concepts that important concepts point to
        
        Args:
            top_k: Number of top concepts to return
            
        Returns:
            Dict mapping concept_id -> ConceptImportance
        """
        G = self._build_networkx_graph()
        
        if G.number_of_nodes() == 0:
            return {}
        
        # Compute different centrality measures
        try:
            degree_cent = nx.degree_centrality(G)
        except Exception:
            degree_cent = {n: 0.0 for n in G.nodes()}
            
        try:
            betweenness_cent = nx.betweenness_centrality(G)
        except Exception:
            betweenness_cent = {n: 0.0 for n in G.nodes()}
            
        try:
            pagerank = nx.pagerank(G, alpha=0.85)
        except Exception:
            pagerank = {n: 1.0 / G.number_of_nodes() for n in G.nodes()}
        
        # Detect communities for each node
        communities = self._detect_communities()
        
        # Build ConceptImportance objects
        importance: Dict[str, ConceptImportance] = {}
        
        for node_id in G.nodes():
            node_data = G.nodes[node_id]
            
            # Combined score (weighted average)
            combined = (
                self.CENTRALITY_WEIGHTS["degree"] * degree_cent.get(node_id, 0) +
                self.CENTRALITY_WEIGHTS["betweenness"] * betweenness_cent.get(node_id, 0) +
                self.CENTRALITY_WEIGHTS["pagerank"] * pagerank.get(node_id, 0)
            )
            
            importance[node_id] = ConceptImportance(
                concept_id=node_id,
                title=node_data.get("title", node_id),
                degree_centrality=degree_cent.get(node_id, 0),
                betweenness_centrality=betweenness_cent.get(node_id, 0),
                pagerank=pagerank.get(node_id, 0),
                combined_score=combined,
                community_id=communities.get(node_id, 0),
            )
        
        # Cache results
        self._centrality_cache = {k: v.combined_score for k, v in importance.items()}
        self._analytics_computed = True
        
        return importance
    
    def _detect_communities(self) -> Dict[str, int]:
        """
        Detect communities (clusters) of related concepts.
        
        Uses Louvain algorithm on undirected version of graph.
        
        Returns:
            Dict mapping concept_id -> community_id
        """
        if self._community_cache:
            return self._community_cache
            
        G = self._build_networkx_graph()
        
        if G.number_of_nodes() == 0:
            return {}
        
        # Convert to undirected for community detection
        G_undirected = G.to_undirected()
        
        try:
            # Use greedy modularity communities (built-in, no extra deps)
            from networkx.algorithms.community import greedy_modularity_communities
            communities = list(greedy_modularity_communities(G_undirected))
            
            community_map: Dict[str, int] = {}
            for idx, community in enumerate(communities):
                for node in community:
                    community_map[node] = idx
                    
            self._community_cache = community_map
            logger.info(f"Detected {len(communities)} communities")
            
        except Exception as e:
            logger.warning(f"Community detection failed: {e}")
            # Fallback: each node is its own community
            self._community_cache = {n: i for i, n in enumerate(G.nodes())}
        
        return self._community_cache
    
    def get_communities(self) -> List[Community]:
        """
        Get list of concept communities with metadata.
        
        Returns:
            List of Community objects with names and central concepts
        """
        G = self._build_networkx_graph()
        community_map = self._detect_communities()
        importance = self.compute_centrality()
        
        # Group concepts by community
        community_concepts: Dict[int, List[str]] = {}
        for concept_id, comm_id in community_map.items():
            if comm_id not in community_concepts:
                community_concepts[comm_id] = []
            community_concepts[comm_id].append(concept_id)
        
        communities: List[Community] = []
        
        for comm_id, concepts in community_concepts.items():
            # Find most important concept in community
            sorted_by_importance = sorted(
                concepts,
                key=lambda c: importance.get(c, ConceptImportance(c, "", 0, 0, 0, 0, 0)).combined_score,
                reverse=True
            )
            central_concept = sorted_by_importance[0] if sorted_by_importance else ""
            
            # Extract keywords from all concepts in community
            all_keywords: Set[str] = set()
            for c in concepts:
                node_data = G.nodes.get(c, {})
                keywords = node_data.get("keywords", "").split()
                all_keywords.update(keywords)
            
            # Generate community name from central concept
            central_title = importance.get(central_concept, ConceptImportance("", "", 0, 0, 0, 0, 0)).title
            name = f"{central_title} Group" if central_title else f"Community {comm_id}"
            
            communities.append(Community(
                community_id=comm_id,
                name=name,
                concepts=concepts,
                central_concept=central_concept,
                keywords=list(all_keywords)[:10],  # Top 10 keywords
            ))
        
        return communities
    
    def rank_concepts(
        self,
        candidates: List[str],
        boost_centrality: float = 0.3,
        boost_community_match: float = 0.2,
        query_community: Optional[int] = None,
    ) -> List[Tuple[str, float]]:
        """
        Rank candidate concepts by importance and relevance.
        
        Args:
            candidates: List of concept IDs to rank
            boost_centrality: Weight for centrality score (0-1)
            boost_community_match: Bonus for same community as query
            query_community: Community ID of query context
            
        Returns:
            List of (concept_id, score) sorted by score descending
        """
        if not self._analytics_computed:
            self.compute_centrality()
        
        community_map = self._detect_communities()
        
        ranked: List[Tuple[str, float]] = []
        
        for concept_id in candidates:
            base_score = 1.0
            
            # Add centrality boost
            centrality = self._centrality_cache.get(concept_id, 0.0)
            score = base_score + (boost_centrality * centrality)
            
            # Add community match bonus
            if query_community is not None:
                concept_community = community_map.get(concept_id, -1)
                if concept_community == query_community:
                    score += boost_community_match
            
            ranked.append((concept_id, score))
        
        # Sort by score descending
        ranked.sort(key=lambda x: x[1], reverse=True)
        
        return ranked
    
    def prune_concepts(
        self,
        concepts: List[str],
        max_output: int = 5,
        min_centrality: float = 0.1,
        prefer_different_communities: bool = True,
    ) -> AnalyticsResult:
        """
        Prune concepts to output only the most important ones.
        
        Smart pruning:
        1. Filter by minimum centrality
        2. Rank by combined score
        3. Ensure diversity (different communities if possible)
        
        Args:
            concepts: Full list of candidate concepts
            max_output: Maximum concepts to return
            min_centrality: Minimum centrality threshold
            prefer_different_communities: Avoid returning too many from same community
            
        Returns:
            AnalyticsResult with top concepts and pruning stats
        """
        if not self._analytics_computed:
            self.compute_centrality()
        
        importance = self.compute_centrality()
        community_map = self._detect_communities()
        
        # Filter by centrality threshold
        filtered = [
            c for c in concepts
            if self._centrality_cache.get(c, 0) >= min_centrality
        ]
        
        # Sort by combined score
        sorted_concepts = sorted(
            filtered,
            key=lambda c: importance.get(c, ConceptImportance(c, "", 0, 0, 0, 0, 0)).combined_score,
            reverse=True
        )
        
        # Select with diversity preference
        selected: List[str] = []
        communities_used: Set[int] = set()
        
        if prefer_different_communities:
            # First pass: one per community
            for c in sorted_concepts:
                if len(selected) >= max_output:
                    break
                comm = community_map.get(c, -1)
                if comm not in communities_used:
                    selected.append(c)
                    communities_used.add(comm)
            
            # Second pass: fill remaining slots
            for c in sorted_concepts:
                if len(selected) >= max_output:
                    break
                if c not in selected:
                    selected.append(c)
        else:
            selected = sorted_concepts[:max_output]
        
        # Build result
        pruned = [c for c in concepts if c not in selected]
        memory_saved = (len(pruned) / len(concepts) * 100) if concepts else 0.0
        
        top_importance = [importance[c] for c in selected if c in importance]
        communities = self.get_communities()
        
        return AnalyticsResult(
            top_concepts=top_importance,
            communities=communities,
            pruned_concepts=pruned,
            memory_saved_percent=memory_saved,
        )
    
    def get_concept_community(self, concept_id: str) -> Optional[int]:
        """Get community ID for a specific concept."""
        if not self._community_cache:
            self._detect_communities()
        return self._community_cache.get(concept_id)
    
    def get_community_concepts(self, community_id: int) -> List[str]:
        """Get all concepts in a community."""
        if not self._community_cache:
            self._detect_communities()
        return [c for c, comm in self._community_cache.items() if comm == community_id]
    
    def get_importance_score(self, concept_id: str) -> float:
        """Get cached importance score for a concept."""
        if not self._analytics_computed:
            self.compute_centrality()
        return self._centrality_cache.get(concept_id, 0.0)
    
    def invalidate_cache(self) -> None:
        """Invalidate all cached analytics (call after KG changes)."""
        self._nx_graph = None
        self._centrality_cache = {}
        self._community_cache = {}
        self._analytics_computed = False
        logger.info("Graph analytics cache invalidated")


# Singleton instance
_analytics_instance: Optional[GraphAnalyticsService] = None


def get_graph_analytics(kg: KnowledgeGraphServiceV3) -> GraphAnalyticsService:
    """Get or create graph analytics service singleton."""
    global _analytics_instance
    if _analytics_instance is None:
        _analytics_instance = GraphAnalyticsService(kg)
    return _analytics_instance
