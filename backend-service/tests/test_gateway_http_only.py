"""GATEWAY_TLS=off turns the gateway into a plain-HTTP origin for a TLS-terminating proxy."""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEMPLATE = ROOT / "gateway/nginx/templates/default.conf.template"
SCRIPT = ROOT / "gateway/nginx/render-http-only.sh"


def _render(tmp_path: Path, trusted: str = "10.77.0.1") -> str:
    text = TEMPLATE.read_text()
    for name, value in {
        "GATEWAY_SERVER_NAME": "api.example.test",
        "GATEWAY_SSL_CERT_PATH": "/etc/ssl/c.pem",
        "GATEWAY_SSL_KEY_PATH": "/etc/ssl/k.pem",
    }.items():
        text = text.replace("${%s}" % name, value)
    conf = tmp_path / "default.conf"
    conf.write_text(text)
    subprocess.run(["sh", str(SCRIPT), str(conf)], check=True, env={"GATEWAY_TRUSTED_PROXY": trusted, "PATH": "/usr/bin:/bin"})
    return conf.read_text()


def test_http_only_mode_has_one_server_on_port_80_and_no_tls(tmp_path):
    out = _render(tmp_path)

    assert out.count("\nserver {") == 1
    assert "listen 80;" in out and "listen [::]:80;" in out
    for forbidden in ("443", "ssl_", "http2 on", "return 301 https://"):
        assert forbidden not in out


def test_http_only_mode_keeps_the_proxy_rules_and_trusts_the_edge(tmp_path):
    out = _render(tmp_path, trusted="10.77.0.1")
    original = TEMPLATE.read_text()

    assert "set_real_ip_from 10.77.0.1;" in out
    assert "real_ip_header   CF-Connecting-IP;" in out
    # only the redirect block's three locations (acme, health, catch-all) went away
    assert out.count("limit_req zone=") == original.count("limit_req zone=")
    assert out.count("location ") == original.count("location ") - 3
    assert "map $http_upgrade $connection_upgrade" in out


def test_compose_wires_the_switch_and_defaults_to_tls_on():
    compose = (ROOT / "docker-compose.yml").read_text()
    assert "GATEWAY_TLS: ${GATEWAY_TLS:-on}" in compose
    assert "render-http-only.sh" in compose
