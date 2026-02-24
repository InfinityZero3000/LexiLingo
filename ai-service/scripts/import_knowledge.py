#!/usr/bin/env python3
"""
Import knowledge from JSON file to KuzuDB knowledge graph.

Usage:
    python import_knowledge.py [--json-path PATH] [--db-path PATH] [--clear]

Examples:
    # Import extended knowledge (default)
    python import_knowledge.py
    
    # Import with custom paths
    python import_knowledge.py --json-path ../data/custom_knowledge.json
    
    # Clear existing and import fresh
    python import_knowledge.py --clear
"""

import json
import os
import sys
import argparse
import logging
from pathlib import Path

# Add parent to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

import kuzu

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


def escape_string(s: str) -> str:
    """Escape string for Cypher query."""
    if s is None:
        return ""
    return s.replace("'", "\\'").replace('"', '\\"')


def import_knowledge(json_path: str, db_path: str, clear_existing: bool = False) -> dict:
    """
    Import knowledge from JSON file to KuzuDB.
    
    Args:
        json_path: Path to JSON file with concepts and edges
        db_path: Path to KuzuDB database directory
        clear_existing: If True, clear existing concepts before import
        
    Returns:
        Dict with import statistics
    """
    stats = {
        "concepts_added": 0,
        "concepts_skipped": 0,
        "edges_added": 0,
        "edges_skipped": 0,
        "errors": []
    }
    
    # Load JSON data
    logger.info(f"Loading knowledge from: {json_path}")
    with open(json_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    concepts = data.get("concepts", [])
    edges = data.get("edges", [])
    logger.info(f"Found {len(concepts)} concepts and {len(edges)} edges to import")
    
    # Connect to KuzuDB
    logger.info(f"Connecting to KuzuDB: {db_path}")
    db = kuzu.Database(db_path)
    conn = kuzu.Connection(db)
    
    # Ensure schema exists
    try:
        conn.execute("CREATE NODE TABLE IF NOT EXISTS Concept(id STRING PRIMARY KEY, title STRING, keywords STRING)")
        conn.execute("CREATE REL TABLE IF NOT EXISTS Edge(FROM Concept TO Concept, relation STRING)")
    except Exception as e:
        logger.warning(f"Schema may already exist: {e}")
    
    # Clear existing if requested
    if clear_existing:
        logger.warning("Clearing existing concepts and edges...")
        try:
            conn.execute("MATCH (c:Concept) WHERE c.id STARTS WITH 'concept:vocab.' OR c.id STARTS WITH 'concept:idiom.' OR c.id STARTS WITH 'concept:phrasal.' OR c.id STARTS WITH 'concept:conversation.' OR c.id STARTS WITH 'concept:pronunciation.' DETACH DELETE c")
            logger.info("Cleared existing extended concepts")
        except Exception as e:
            logger.warning(f"Could not clear: {e}")
    
    # Import concepts
    logger.info("Importing concepts...")
    for concept in concepts:
        concept_id = concept.get("id", "")
        title = escape_string(concept.get("title", ""))
        keywords = escape_string(concept.get("keywords", ""))
        
        try:
            # Check if exists
            result = conn.execute(f"MATCH (c:Concept) WHERE c.id = '{concept_id}' RETURN c.id")
            exists = len(result.get_as_df()) > 0 if hasattr(result, 'get_as_df') else False  # type: ignore[union-attr]
            
            if exists:
                # Update existing
                conn.execute(f"""
                    MATCH (c:Concept) 
                    WHERE c.id = '{concept_id}' 
                    SET c.title = '{title}', c.keywords = '{keywords}'
                """)
                stats["concepts_skipped"] += 1
                logger.debug(f"Updated existing: {concept_id}")
            else:
                # Insert new
                conn.execute(f"""
                    CREATE (c:Concept {{
                        id: '{concept_id}',
                        title: '{title}',
                        keywords: '{keywords}'
                    }})
                """)
                stats["concepts_added"] += 1
                logger.debug(f"Added: {concept_id}")
                
        except Exception as e:
            error_msg = f"Error adding concept {concept_id}: {e}"
            logger.error(error_msg)
            stats["errors"].append(error_msg)
    
    # Import edges
    logger.info("Importing edges...")
    for edge in edges:
        from_id = edge.get("from", "")
        to_id = edge.get("to", "")
        relation = escape_string(edge.get("relation", "related_to"))
        
        try:
            # Check if both nodes exist
            from_result = conn.execute(f"MATCH (c:Concept) WHERE c.id = '{from_id}' RETURN c.id")
            to_result = conn.execute(f"MATCH (c:Concept) WHERE c.id = '{to_id}' RETURN c.id")
            
            from_exists = len(from_result.get_as_df()) > 0 if hasattr(from_result, 'get_as_df') else False  # type: ignore[union-attr]
            to_exists = len(to_result.get_as_df()) > 0 if hasattr(to_result, 'get_as_df') else False  # type: ignore[union-attr]
            
            if not from_exists or not to_exists:
                logger.warning(f"Skipping edge {from_id} -> {to_id}: node(s) not found")
                stats["edges_skipped"] += 1
                continue
            
            # Check if edge exists
            edge_result = conn.execute(f"""
                MATCH (a:Concept)-[e:Edge]->(b:Concept) 
                WHERE a.id = '{from_id}' AND b.id = '{to_id}' 
                RETURN e.relation
            """)
            edge_exists = len(edge_result.get_as_df()) > 0 if hasattr(edge_result, 'get_as_df') else False  # type: ignore[union-attr]
            
            if edge_exists:
                stats["edges_skipped"] += 1
                logger.debug(f"Edge exists: {from_id} -> {to_id}")
            else:
                conn.execute(f"""
                    MATCH (a:Concept), (b:Concept) 
                    WHERE a.id = '{from_id}' AND b.id = '{to_id}' 
                    CREATE (a)-[e:Edge {{relation: '{relation}'}}]->(b)
                """)
                stats["edges_added"] += 1
                logger.debug(f"Added edge: {from_id} -[{relation}]-> {to_id}")
                
        except Exception as e:
            error_msg = f"Error adding edge {from_id} -> {to_id}: {e}"
            logger.error(error_msg)
            stats["errors"].append(error_msg)
    
    logger.info("=" * 50)
    logger.info("Import Summary:")
    logger.info(f"  Concepts added: {stats['concepts_added']}")
    logger.info(f"  Concepts updated/skipped: {stats['concepts_skipped']}")
    logger.info(f"  Edges added: {stats['edges_added']}")
    logger.info(f"  Edges skipped: {stats['edges_skipped']}")
    if stats["errors"]:
        logger.warning(f"  Errors: {len(stats['errors'])}")
    logger.info("=" * 50)
    
    return stats


def main():
    parser = argparse.ArgumentParser(description="Import knowledge to KuzuDB")
    parser.add_argument(
        "--json-path",
        default=str(Path(__file__).parent.parent / "data" / "knowledge_extended.json"),
        help="Path to JSON knowledge file"
    )
    parser.add_argument(
        "--db-path",
        default=str(Path(__file__).parent.parent / "data" / "kuzu_db"),
        help="Path to KuzuDB database"
    )
    parser.add_argument(
        "--clear",
        action="store_true",
        help="Clear existing extended concepts before import"
    )
    
    args = parser.parse_args()
    
    if not os.path.exists(args.json_path):
        logger.error(f"JSON file not found: {args.json_path}")
        sys.exit(1)
    
    stats = import_knowledge(args.json_path, args.db_path, args.clear)
    
    if stats["errors"]:
        sys.exit(1)
    
    sys.exit(0)


if __name__ == "__main__":
    main()
