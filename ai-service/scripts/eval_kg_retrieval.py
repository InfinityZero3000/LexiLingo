"""Does this KG's lexical retrieval beat the alternatives?

Usage:  python scripts/eval_kg_retrieval.py [path/to/kuzu_runtime_copy.db]


Three retrievers over the same 15k-concept corpus (title + keywords):
  A  shipped query_concepts  — IDF-weighted overlap + CEFR boost + title boost
  B  BM25                    — rank_bm25, the standard lexical baseline
  C  dense vectors           — all-MiniLM-L6-v2 cosine

Two query sets:
  self   a node's own title  (lexical has the answer handed to it)
  para   LLM-written learner phrasings of the same topic (nobody is handed it)
"""
import collections
import json
import os
import re
import sys

import kuzu

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
# Point at a COPY of the runtime graph — Kuzu takes a lock, so this must not be
# the database a running ai-service has open.
os.environ["KUZU_DB_PATH"] = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "data", "kuzu_runtime.db")

from api.services.kg_service_v3 import KnowledgeGraphServiceV3  # noqa: E402

kg = KnowledgeGraphServiceV3()
concepts = kg.get_concepts()
ids = list(concepts)
docs = [f"{concepts[i]['title']} {concepts[i]['keywords']}" for i in ids]
print(f"corpus: {len(ids)} concepts", flush=True)

TOK = re.compile(r"[a-z0-9_']+")
tokenised = [[t for t in TOK.findall(d.lower()) if len(t) >= 3] for d in docs]

from rank_bm25 import BM25Okapi  # noqa: E402

bm25 = BM25Okapi(tokenised)
print("bm25 ready", flush=True)

from sentence_transformers import SentenceTransformer  # noqa: E402
import numpy as np  # noqa: E402

model = SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")
EMB_PATH = os.path.join(ROOT, "data", "eval", "concept_emb.npy")
if os.path.exists(EMB_PATH):
    emb = np.load(EMB_PATH)
else:
    # keywords blobs run to 20k chars; the encoder truncates at 256 tokens
    # anyway, so trim explicitly to keep encoding time sane
    trimmed = [" ".join(d.split()[:60]) for d in docs]
    emb = model.encode(trimmed, batch_size=256, show_progress_bar=True, normalize_embeddings=True)
    np.save(EMB_PATH, emb)
print(f"embeddings ready {emb.shape}", flush=True)


def a_shipped(query, level, k):
    return [n["id"] for n in kg.query_concepts(query, learner_level=level, top_k=k)]


def b_bm25(query, level, k):
    toks = [t for t in TOK.findall(query.lower()) if len(t) >= 3]
    if not toks:
        return []
    scores = bm25.get_scores(toks)
    top = np.argpartition(-scores, range(min(k, len(scores))))[:k]
    return [ids[i] for i in top if scores[i] > 0]


def c_dense(query, level, k):
    qv = model.encode([query], normalize_embeddings=True, show_progress_bar=False)[0]
    sims = emb @ qv
    top = np.argpartition(-sims, range(min(k, len(sims))))[:k]
    return [ids[i] for i in sorted(top, key=lambda i: -sims[i])]


METHODS = [("A shipped lexical", a_shipped), ("B BM25", b_bm25), ("C dense MiniLM", c_dense)]


def run(name, cases):
    # Two metrics: the exact topic node, and anything belonging to that topic
    # (its functions, vocabulary, phrases all carry the slug). For grounding a
    # chat turn, the family hit is what actually matters — the evidence is on
    # the right subject either way.
    print(f"\n== {name} ({len(cases)} truy vấn) ==")
    for label, fn in METHODS:
        t1 = t5 = f5 = 0
        for query, gold, level in cases:
            res = fn(query, level, 5)
            slug = gold.split("topic:story_", 1)[-1]
            if res[:1] == [gold]:
                t1 += 1
            if gold in res:
                t5 += 1
            if any(slug in r for r in res):
                f5 += 1
        n = len(cases)
        print(
            f"  {label:20} exact-top1 {t1:4}/{n} ({t1/n*100:5.1f}%)"
            f"   exact-top5 {t5:4}/{n} ({t5/n*100:5.1f}%)"
            f"   ĐÚNG-TOPIC-top5 {f5:4}/{n} ({f5/n*100:5.1f}%)"
        )


self_cases = [
    (m["title"], i, m["level"]) for i, m in concepts.items() if i.startswith("topic:")
]
run("SELF — query = chính title của topic", self_cases)

para_path = os.path.join(ROOT, "data", "eval", "topic_paraphrases.json")
if os.path.exists(para_path):
    data = json.load(open(para_path))
    para_cases = [
        (q, d["topic_id"], d["level"]) for d in data for q in d["queries"]
    ]
    run("PARA — query = cách người học nói", para_cases)

    print("\nVí dụ (PARA):")
    for query, gold, level in para_cases[:4]:
        print(f"  Q: {query}   [gold={gold.split(':')[-1]}]")
        for label, fn in METHODS:
            res = fn(query, level, 3)
            mark = "OK " if gold in res else "   "
            print(f"     {mark}{label:20} {[r.split(':')[-1][:26] for r in res]}")
else:
    print("\n(chưa có topic_paraphrases.json)")
