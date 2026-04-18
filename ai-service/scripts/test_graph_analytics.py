#!/usr/bin/env python3
"""
Test script for Graph Analytics Service.

Run with: python test_graph_analytics.py
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

def test_imports():
    """Test all imports work."""
    print("1. Testing imports...")
    try:
        from api.services.kg_service_v3 import KnowledgeGraphServiceV3
        print("    KnowledgeGraphServiceV3")
        
        from api.services.graph_analytics import GraphAnalyticsService, get_graph_analytics
        print("    GraphAnalyticsService")
        
        from api.services.retrieval_service_v3 import RetrievalServiceV3, RetrievalConfig
        print("    RetrievalServiceV3")
        
        return True
    except Exception as e:
        print(f"    Import error: {e}")
        return False


def test_kg_init():
    """Test KG initialization."""
    print("\n2. Testing KG initialization...")
    try:
        from api.services.kg_service_v3 import KnowledgeGraphServiceV3
        kg = KnowledgeGraphServiceV3()
        count = kg.get_concept_count()
        print(f"    KG initialized with {count} concepts")
        return kg
    except Exception as e:
        print(f"    KG init error: {e}")
        return None


def test_centrality(kg):
    """Test centrality analysis."""
    print("\n3. Testing centrality analysis...")
    try:
        from api.services.graph_analytics import get_graph_analytics
        
        analytics = get_graph_analytics(kg)
        importance = analytics.compute_centrality()
        
        print(f"    Computed centrality for {len(importance)} concepts")
        
        # Top 5
        top_5 = sorted(importance.values(), key=lambda x: x.combined_score, reverse=True)[:5]
        print("\n   Top 5 concepts by centrality:")
        for i, c in enumerate(top_5, 1):
            print(f"     {i}. {c.title}")
            print(f"        Degree: {c.degree_centrality:.4f}")
            print(f"        Betweenness: {c.betweenness_centrality:.4f}")
            print(f"        PageRank: {c.pagerank:.4f}")
            print(f"        Combined: {c.combined_score:.4f}")
            print(f"        Community: {c.community_id}")
        
        return analytics
    except Exception as e:
        print(f"    Centrality error: {e}")
        import traceback
        traceback.print_exc()
        return None


def test_communities(analytics):
    """Test community detection."""
    print("\n4. Testing community detection...")
    try:
        communities = analytics.get_communities()
        print(f"    Detected {len(communities)} communities")
        
        for c in communities:
            print(f"\n   Community {c.community_id}: {c.name}")
            print(f"     Central concept: {c.central_concept}")
            print(f"     Size: {len(c.concepts)} concepts")
            print(f"     Keywords: {', '.join(c.keywords[:5])}")
        
        return True
    except Exception as e:
        print(f"    Community error: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_pruning(analytics):
    """Test smart pruning."""
    print("\n5. Testing smart pruning...")
    try:
        importance = analytics.compute_centrality()
        all_concepts = list(importance.keys())
        
        result = analytics.prune_concepts(
            all_concepts,
            max_output=5,
            prefer_different_communities=True
        )
        
        print(f"   Input: {len(all_concepts)} concepts")
        print(f"   Output: {len(result.top_concepts)} concepts")
        print(f"   Pruned: {len(result.pruned_concepts)} concepts")
        print(f"   Memory saved: {result.memory_saved_percent:.1f}%")
        
        print("\n   Selected concepts (with diversity):")
        for c in result.top_concepts:
            print(f"     - {c.title} (community {c.community_id})")
        
        return True
    except Exception as e:
        print(f"    Pruning error: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_retrieval(kg):
    """Test enhanced retrieval service."""
    print("\n6. Testing enhanced retrieval service...")
    try:
        from api.services.retrieval_service_v3 import RetrievalServiceV3, RetrievalConfig
        
        config = RetrievalConfig(
            use_centrality_ranking=True,
            use_community_detection=True,
            enable_pruning=True,
            max_output_concepts=5,
        )
        
        retrieval = RetrievalServiceV3(kg, config)
        summary = retrieval.get_analytics_summary()
        
        print(f"    Retrieval service initialized")
        print(f"   Total concepts: {summary['total_concepts']}")
        print(f"   Total communities: {summary['total_communities']}")
        
        print("\n   Top concepts in retrieval:")
        for c in summary['top_concepts'][:3]:
            print(f"     - {c['title']} (score: {c['score']}, community: {c['community']})")
        
        return True
    except Exception as e:
        print(f"    Retrieval error: {e}")
        import traceback
        traceback.print_exc()
        return False


def main():
    print("=" * 60)
    print("Graph Analytics Service Test")
    print("=" * 60)
    
    # Run tests
    if not test_imports():
        print("\n Import test failed!")
        return 1
    
    kg = test_kg_init()
    if not kg:
        print("\n KG init test failed!")
        return 1
    
    analytics = test_centrality(kg)
    if not analytics:
        print("\n Centrality test failed!")
        return 1
    
    if not test_communities(analytics):
        print("\n Community test failed!")
        return 1
    
    if not test_pruning(analytics):
        print("\n Pruning test failed!")
        return 1
    
    if not test_retrieval(kg):
        print("\n Retrieval test failed!")
        return 1
    
    print("\n" + "=" * 60)
    print(" All tests passed!")
    print("=" * 60)
    return 0


if __name__ == "__main__":
    sys.exit(main())
