from pathlib import Path
import sys


BENCHMARK_DIR = Path(__file__).resolve().parents[2] / "model-development" / "benchmark"
sys.path.insert(0, str(BENCHMARK_DIR))
