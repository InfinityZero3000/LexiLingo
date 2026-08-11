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
    requirements = _requirements(ROOT / "requirements.txt")
    constraints = _requirements(ROOT / "constraints-ai.txt")

    expected = {
        "numpy": "1.26.4",
        "torch": "2.13.0",
        "transformers": "4.57.6",
        "sentence-transformers": "4.1.0",
        "faster-whisper": "1.2.1",
        "moonshine-voice": "0.1.0",
        "sherpa-onnx": "1.13.4",
        "scipy": "1.17.1",
    }
    for package, version in expected.items():
        pinned = constraints[package]
        assert pinned.specifier == f"=={version}"
        assert Version(version) in requirements[package].specifier

    assert Version("2.0.0") not in requirements["numpy"].specifier
    assert Version("5.0.0") not in requirements["transformers"].specifier
