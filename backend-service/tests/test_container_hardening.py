"""Unit tests to verify container hardening and network port isolation configurations."""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]


def _read(name: str) -> str:
    return (ROOT / name).read_text(encoding="utf-8")


def test_production_image_uses_pinned_multi_stage_runtime():
    # Read backend production Dockerfile
    dockerfile = _read("backend-service/Dockerfile.prod")

    assert "USER appuser" in dockerfile
    assert "HEALTHCHECK" in dockerfile
    assert "python:3.13-slim" in dockerfile


def test_compose_ports_restricted_to_loopback():
    compose = _read("docker-compose.yml")

    # Find all ports: sections and extract their mappings line-by-line
    lines = compose.splitlines()
    all_mapped_ports = []
    in_ports = False
    for line in lines:
        if line.strip().startswith("ports:"):
            in_ports = True
            continue
        if in_ports:
            m = re.match(r'^\s+-\s*"([^"]+)"', line)
            if m:
                all_mapped_ports.append(m.group(1))
            else:
                in_ports = False

    # Ensure postgres, redis, prometheus, and grafana bind strictly to 127.0.0.1
    assert "127.0.0.1:5432:5432" in all_mapped_ports
    assert "127.0.0.1:6379:6379" in all_mapped_ports
    assert "127.0.0.1:9090:9090" in all_mapped_ports
    assert "127.0.0.1:3001:3000" in all_mapped_ports

    # Ensure only gateway ports are publicly exposed (0.0.0.0)
    public_ports = [p for p in all_mapped_ports if "127.0.0.1" not in p]
    
    assert len(public_ports) == 2
    assert "80:80" in public_ports
    assert "443:443" in public_ports
