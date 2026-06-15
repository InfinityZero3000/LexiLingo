"""Licensed Content ETL CLI.

Usage:
    python -m api.services.content_etl.cli list
    python -m api.services.content_etl.cli sync --sources oewn,cmudict --write
    python -m api.services.content_etl.cli validate --source oewn --version 2025
    python -m api.services.content_etl.cli activate --source oewn --version 2025
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Optional

try:
    import typer
except ImportError:
    print("typer is required: pip install typer", file=sys.stderr)
    sys.exit(1)

from api.services.content_etl.contracts import SourceName
from api.services.content_etl.registry import (
    SourceRegistryError,
    get_source_definition,
    list_source_definitions,
)
from api.services.content_etl.storage import SnapshotStorage, StorageIntegrityError


app = typer.Typer(
    name="content-etl",
    help="Licensed Content ETL — manage approved open-dataset snapshots.",
    add_completion=False,
)


def _get_storage() -> SnapshotStorage:
    try:
        from api.core.config import get_settings
        root = get_settings().CONTENT_ETL_STORAGE_ROOT
    except Exception:
        root = "/data/content-etl"
    return SnapshotStorage(root)


@app.command("list")
def list_sources() -> None:
    """List all registered ETL sources and their enablement status."""
    definitions = list_source_definitions()
    typer.echo(f"{'Source':<20} {'Enabled':<10} {'Licenses'}")
    typer.echo("-" * 70)
    for defn in definitions:
        enabled = "yes" if defn.default_enabled else "no"
        licenses = ", ".join(lic.value for lic in defn.allowed_licenses)
        typer.echo(f"{defn.source_name.value:<20} {enabled:<10} {licenses}")


@app.command("sync")
def sync(
    sources: str = typer.Option(
        ...,
        "--sources",
        help="Comma-separated source IDs to sync (e.g. oewn,cmudict)",
    ),
    write: bool = typer.Option(
        False,
        "--write",
        help="Actually write output; omit for dry-run",
    ),
    storage_root: Optional[str] = typer.Option(
        None,
        "--storage-root",
        help="Override ETL storage root directory",
    ),
) -> None:
    """Download and normalize approved dataset snapshots (dry-run unless --write)."""
    source_ids = [s.strip() for s in sources.split(",") if s.strip()]
    if not source_ids:
        typer.echo("No sources specified.", err=True)
        raise typer.Exit(1)

    dry_run = not write
    if dry_run:
        typer.echo("[dry-run] No files will be written.")

    for source_id in source_ids:
        try:
            defn = get_source_definition(source_id)
        except SourceRegistryError as exc:
            typer.echo(f"ERROR: {exc}", err=True)
            raise typer.Exit(1) from exc

        typer.echo(
            f"[{'dry-run' if dry_run else 'sync'}] {defn.source_name.value}: "
            f"{defn.official_url or '(admin_upload)'}"
        )

    if dry_run:
        typer.echo("Dry-run complete. Pass --write to persist.")
    else:
        typer.echo(
            "Sync requested. Connect a real adapter and pass raw_bytes to ETLPipeline.run()."
        )


@app.command("validate")
def validate(
    source: str = typer.Option(..., "--source", help="Source ID (e.g. oewn)"),
    version: str = typer.Option(..., "--version", help="Snapshot version (e.g. 2025)"),
    storage_root: Optional[str] = typer.Option(
        None,
        "--storage-root",
        help="Override ETL storage root directory",
    ),
) -> None:
    """Validate that a snapshot manifest is well-formed and consistent."""
    root = storage_root or None
    try:
        storage = SnapshotStorage(root or "/data/content-etl")
        manifest = storage.read_manifest(source, version)
    except StorageIntegrityError as exc:
        typer.echo(f"ERROR: {exc}", err=True)
        raise typer.Exit(1) from exc
    except Exception as exc:
        typer.echo(f"ERROR: {exc}", err=True)
        raise typer.Exit(1) from exc

    typer.echo(f"Manifest: {source}@{version}")
    typer.echo(f"  Status:    {manifest.status}")
    typer.echo(f"  License:   {manifest.license_id.value}")
    typer.echo(f"  Extracted: {manifest.counts.extracted}")
    typer.echo(f"  Approved:  {manifest.counts.approved}")
    typer.echo(f"  Quarantined: {manifest.counts.quarantined}")
    typer.echo("OK")


@app.command("activate")
def activate(
    source: str = typer.Option(..., "--source", help="Source ID (e.g. oewn)"),
    version: str = typer.Option(..., "--version", help="Snapshot version (e.g. 2025)"),
    storage_root: Optional[str] = typer.Option(
        None,
        "--storage-root",
        help="Override ETL storage root directory",
    ),
) -> None:
    """Activate an approved snapshot, making it the active version."""
    try:
        storage = SnapshotStorage(storage_root or "/data/content-etl")
        active_path = storage.activate(source, version)
    except StorageIntegrityError as exc:
        typer.echo(f"ERROR: {exc}", err=True)
        raise typer.Exit(1) from exc

    typer.echo(f"Activated {source}@{version} → {active_path}")


if __name__ == "__main__":
    app()
