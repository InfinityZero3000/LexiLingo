from tracecag_bench.cli import build_parser


def test_all_command_uses_standard_environment_defaults(monkeypatch):
    monkeypatch.setenv("TRACECAG_BENCHMARK_N", "100")
    monkeypatch.setenv("TRACECAG_BENCHMARK_SEED", "42")
    monkeypatch.setenv("TRACECAG_BENCHMARK_PROFILE", "public_cag_compare")
    monkeypatch.setenv("TRACECAG_BENCHMARK_CACHE_REPEATS", "2")
    monkeypatch.setenv("TRACECAG_BENCHMARK_GENERATION_POLICY", "auto")
    monkeypatch.setenv("TRACECAG_BENCHMARK_EVIDENCE_MODE", "candidate_pool")
    monkeypatch.setenv("TRACECAG_BENCHMARK_DRIFT_SPLIT", "test")
    monkeypatch.setenv("TRACECAG_BENCHMARK_DRIFT_MODE", "tracecag_rapid")
    monkeypatch.setenv("TRACECAG_BENCHMARK_LLM_PROVIDER", "groq")
    monkeypatch.setenv("GROQ_MODEL", "qwen/qwen3-32b")

    args = build_parser().parse_args(["all"])

    assert args.n == 100
    assert args.seed == 42
    assert args.profile == "public_cag_compare"
    assert args.cache_repeats == 2
    assert args.generation_policy == "auto"
    assert args.evidence_mode == "candidate_pool"
    assert args.drift_split == "test"
    assert args.drift_mode == "tracecag_rapid"
    assert args.provider == "groq"
    assert args.model == "qwen/qwen3-32b"


def test_cli_arguments_override_environment_defaults(monkeypatch):
    monkeypatch.setenv("TRACECAG_BENCHMARK_N", "100")
    monkeypatch.setenv("TRACECAG_BENCHMARK_SEED", "42")
    monkeypatch.setenv("GROQ_MODEL", "qwen/qwen3-32b")

    args = build_parser().parse_args(
        ["all", "--n", "5", "--seed", "7", "--model", "custom/model"]
    )

    assert args.n == 5
    assert args.seed == 7
    assert args.model == "custom/model"
