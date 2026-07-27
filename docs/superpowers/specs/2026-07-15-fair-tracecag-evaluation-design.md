# Fair TRACE-CAG Evaluation Design

Public-QA evaluation must keep gold data outside the production pipeline. The runtime receives only the question, candidate documents, and non-oracle state. Answers and supporting titles remain in the evaluator for post-hoc EM/F1 and retrieval metrics.

During validation/test, the online ranker is frozen and IRCoT uses only observable query/retrieval features. Quality metrics use cold observations; warm observations measure cache hit, latency, and token savings. Any provider bypass invalidates the stage.

The evaluation KG is a frozen snapshot that excludes `concept:benchmark.*` data derived from evaluation samples. Cache and KG run on isolated per-stage state. Tests prove no oracle metadata crosses the runtime boundary and no test-time learning occurs.
