#!/usr/bin/env python3
"""Build, validate, and promote a clean production Kuzu graph."""

from __future__ import annotations

import argparse
import gc
import os
import sys
import time
from pathlib import Path


AI_SERVICE_ROOT = Path(__file__).resolve().parent.parent
if str(AI_SERVICE_ROOT) not in sys.path:
    sys.path.insert(0, str(AI_SERVICE_ROOT))


def _validate_target(target: Path) -> Path:
    resolved = target.resolve()
    if resolved in {Path("/").resolve(), AI_SERVICE_ROOT.resolve(), AI_SERVICE_ROOT.parent.resolve()}:
        raise ValueError(f"Refusing broad KG target: {resolved}")
    if resolved.parent != (AI_SERVICE_ROOT / "data").resolve():
        raise ValueError(f"Runtime KG target must be directly under {AI_SERVICE_ROOT / 'data'}")
    return resolved


def _counts(path: Path) -> tuple[int, int]:
    import kuzu

    db = kuzu.Database(str(path), read_only=True)
    conn = kuzu.Connection(db)
    total_result = conn.execute("MATCH (c:Concept) RETURN count(c)")
    benchmark_result = conn.execute(
        "MATCH (c:Concept) WHERE c.id STARTS WITH 'concept:benchmark.' RETURN count(c)"
    )
    total = int(total_result.get_next()[0])
    benchmark = int(benchmark_result.get_next()[0])
    conn.close()
    db.close()
    return total, benchmark


def validate(path: Path) -> int:
    total, benchmark = _counts(path)
    if total <= 0:
        raise RuntimeError(f"Runtime KG is empty: {path}")
    if benchmark:
        raise RuntimeError(f"Runtime KG contains {benchmark} benchmark concepts: {path}")
    print(f"Validated runtime KG: concepts={total}, benchmark_concepts=0, path={path}")
    return total


def rebuild(target: Path, contaminated_source: Path | None = None) -> Path | None:
    target = _validate_target(target)
    replacement = target.with_name(f"{target.name}.rebuild.{os.getpid()}")
    if replacement.exists():
        raise FileExistsError(f"Replacement path already exists: {replacement}")

    env_names = (
        "KUZU_DB_PATH",
        "KG_DATA_DIR",
        "TRACECAG_KG_ALLOW_BENCHMARK",
        "TRACECAG_KG_STRICT_SNAPSHOT",
    )
    previous_env = {name: os.environ.get(name) for name in env_names}
    previous_setting = None
    try:
        os.environ["KUZU_DB_PATH"] = str(replacement)
        os.environ["KG_DATA_DIR"] = str((AI_SERVICE_ROOT / "data" / "kg").resolve())
        os.environ.pop("TRACECAG_KG_ALLOW_BENCHMARK", None)
        os.environ.pop("TRACECAG_KG_STRICT_SNAPSHOT", None)

        from api.services import kg_service_v3 as kg_module

        previous_setting = kg_module.settings.KUZU_DB_PATH
        kg_module.settings.KUZU_DB_PATH = str(replacement)
        kg = kg_module.KnowledgeGraphServiceV3()
        kg._conn.close()
        kg._db.close()
        del kg
        gc.collect()
    finally:
        if previous_setting is not None:
            kg_module.settings.KUZU_DB_PATH = previous_setting
        for name, value in previous_env.items():
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value
    validate(replacement)

    timestamp = time.strftime("%Y%m%d-%H%M%S", time.gmtime())
    quarantine = target.with_name(f"{target.name}.quarantine.{timestamp}")
    source = _validate_target(contaminated_source) if contaminated_source else target
    if source != target and target.exists():
        raise FileExistsError(f"Refusing to overwrite existing runtime target: {target}")
    source_metadata = Path(f"{source}_synced_files.json")
    target_metadata = Path(f"{target}_synced_files.json")
    replacement_metadata = Path(f"{replacement}_synced_files.json")
    quarantine_metadata = Path(f"{quarantine}_synced_files.json")

    if quarantine.exists() or quarantine_metadata.exists():
        raise FileExistsError(f"Quarantine path already exists: {quarantine}")
    try:
        if source.exists():
            source.replace(quarantine)
        if source_metadata.exists():
            source_metadata.replace(quarantine_metadata)
        replacement.replace(target)
        if replacement_metadata.exists():
            replacement_metadata.replace(target_metadata)
        validate(target)
    except Exception:
        if target.exists() and not replacement.exists():
            target.replace(replacement)
        if target_metadata.exists() and not replacement_metadata.exists():
            target_metadata.replace(replacement_metadata)
        if quarantine.exists() and not source.exists():
            quarantine.replace(source)
        if quarantine_metadata.exists() and not source_metadata.exists():
            quarantine_metadata.replace(source_metadata)
        raise
    return quarantine if quarantine.exists() else None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", type=Path, required=True)
    parser.add_argument(
        "--contaminated-source",
        type=Path,
        help="Optional legacy runtime DB to quarantine when target path changes",
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--apply", action="store_true")
    mode.add_argument("--dry-run", action="store_true")
    mode.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()

    target = _validate_target(args.target)
    if args.validate_only:
        validate(target)
        return
    if args.dry_run:
        source = _validate_target(args.contaminated_source) if args.contaminated_source else target
        print(f"Would rebuild runtime KG: source={source}, target={target}")
        return
    quarantine = rebuild(target, args.contaminated_source)
    print(f"Promoted clean runtime KG to {target}")
    if quarantine:
        print(f"Contaminated KG quarantined at {quarantine}")


if __name__ == "__main__":
    main()
