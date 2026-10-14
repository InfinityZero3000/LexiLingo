from pathlib import Path

from packaging.requirements import Requirement
from packaging.version import Version


ROOT = Path(__file__).resolve().parents[1]


def _requirements(path: Path) -> dict[str, Requirement]:
    parsed: dict[str, Requirement] = {}
    for raw_line in path.read_text().splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        requirement = Requirement(line)
        parsed[requirement.name.lower()] = requirement
    return parsed


def test_ai_constraints_match_supported_torch_stack():
    """Every pinned constraint must be installable under its requirement range.

    This used to carry a literal version table, which made it a copy of the two
    files rather than a check on them: a bump had to be typed in three places
    and the test only ever failed because someone updated two of them. It broke
    on torch 2.13.0 -> 2.14.0 while both files already agreed.

    What is worth catching is the opposite — a bump landing in one file and not
    the other, which is how `kombu`/`celery` and the admin lockfiles broke CI on
    2026-10-14. pip would install a version the constraint forbids, or refuse to
    resolve at all.
    """
    requirements = _requirements(ROOT / "requirements.txt")
    constraints = _requirements(ROOT / "constraints-ai.txt")

    # The ML stack whose versions have to move together; a constraint for
    # anything here must sit inside what requirements.txt allows.
    pinned_stack = [
        "numpy",
        "torch",
        "transformers",
        "sentence-transformers",
        "faster-whisper",
        "moonshine-voice",
        "sherpa-onnx",
        "scipy",
    ]
    for package in pinned_stack:
        assert package in constraints, f"{package} lost its pin in constraints-ai.txt"
        assert package in requirements, f"{package} left requirements.txt"
        pinned = constraints[package].specifier
        versions = [str(spec.version) for spec in pinned if spec.operator == "=="]
        assert len(versions) == 1, f"{package} is not pinned to one version: {pinned}"
        assert Version(versions[0]) in requirements[package].specifier, (
            f"constraints-ai.txt pins {package}=={versions[0]}, which "
            f"requirements.txt ({requirements[package].specifier}) does not allow"
        )

    # Ceilings that encode real incompatibilities rather than a current version.
    assert Version("2.0.0") not in requirements["numpy"].specifier
    assert Version("5.0.0") not in requirements["transformers"].specifier
