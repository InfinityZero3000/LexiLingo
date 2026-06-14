import os
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
START_SCRIPT = REPO_ROOT / "mcp-server" / "start_production.sh"
SECURITY_WORKFLOW = REPO_ROOT / ".github" / "workflows" / "security.yml"
GITLEAKS_CONFIG = REPO_ROOT / ".gitleaks.toml"


def test_production_start_requires_gemini_api_key_before_side_effects():
    env = os.environ.copy()
    env.pop("GEMINI_API_KEY", None)

    result = subprocess.run(
        ["bash", str(START_SCRIPT)],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        timeout=5,
        check=False,
    )

    assert result.returncode != 0
    assert "GEMINI_API_KEY must be set" in result.stderr
    assert "Checking Ollama service" not in result.stdout


def test_production_start_does_not_embed_or_print_google_api_keys():
    script = START_SCRIPT.read_text()

    assert "AIza" not in script
    assert "${GEMINI_API_KEY:0:" not in script
    assert "Gemini API: configured" in script


def test_security_workflow_scans_current_tree_and_full_history():
    workflow = SECURITY_WORKFLOW.read_text()

    assert "fetch-depth: 0" in workflow
    assert "gitleaks dir" in workflow
    assert "gitleaks git" in workflow
    assert '--log-opts="--all"' in workflow
    assert '"feature/**"' in workflow
    assert "develop" in workflow


def test_legacy_history_allowlist_is_path_scoped():
    config = GITLEAKS_CONFIG.read_text()
    legacy = config.split('description = "Legacy findings predating Phase 1"', 1)[1]

    assert 'condition = "AND"' in legacy
    assert "mcp-server/start_production" in legacy
    assert "mcp-server/tests/test_full" in legacy
