"""Archive extraction with traversal, link, and expansion limits."""

from __future__ import annotations

import os
import shutil
import tarfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath


class ArchiveSecurityError(ValueError):
    """Raised when an archive is unsafe or exceeds extraction limits."""


@dataclass(frozen=True)
class ArchiveLimits:
    max_files: int = 100_000
    max_file_bytes: int = 512 * 1024 * 1024
    max_total_bytes: int = 2 * 1024 * 1024 * 1024


def safe_extract_tar(
    archive_path: str | Path,
    destination: str | Path,
    *,
    requested_members: set[str],
    limits: ArchiveLimits = ArchiveLimits(),
) -> list[Path]:
    archive_path = Path(archive_path)
    destination = Path(destination)
    requested = {_normalize_member_name(name) for name in requested_members}
    if not requested:
        raise ArchiveSecurityError("At least one archive member must be requested")

    with tarfile.open(archive_path, mode="r:*") as archive:
        members = archive.getmembers()
        regular_members: dict[str, tarfile.TarInfo] = {}
        total_bytes = 0

        for member in members:
            normalized_name = _normalize_member_name(member.name)
            if member.issym() or member.islnk():
                raise ArchiveSecurityError("Archive links are not allowed")
            if member.isdir():
                continue
            if not member.isfile():
                raise ArchiveSecurityError(
                    "Archive contains an unsupported non-file member"
                )

            if normalized_name in regular_members:
                raise ArchiveSecurityError(
                    f"Archive contains duplicate member name: {normalized_name}"
                )
            regular_members[normalized_name] = member
            if len(regular_members) > limits.max_files:
                raise ArchiveSecurityError("Archive file-count limit exceeded")
            if member.size > limits.max_file_bytes:
                raise ArchiveSecurityError("Archive per-file byte limit exceeded")
            total_bytes += member.size
            if total_bytes > limits.max_total_bytes:
                raise ArchiveSecurityError(
                    "Archive total decompressed-byte limit exceeded"
                )

        missing = requested - regular_members.keys()
        if missing:
            raise ArchiveSecurityError(
                f"Requested archive members are missing: {sorted(missing)}"
            )

        destination.mkdir(parents=True, exist_ok=False)
        extracted: list[Path] = []
        try:
            for name in sorted(requested):
                member = regular_members[name]
                target = destination.joinpath(*PurePosixPath(name).parts)
                target.parent.mkdir(parents=True, exist_ok=True)
                _require_within_destination(destination, target)
                source = archive.extractfile(member)
                if source is None:
                    raise ArchiveSecurityError(
                        f"Could not read archive member: {name}"
                    )
                with source, target.open("xb") as output:
                    shutil.copyfileobj(source, output, length=1024 * 1024)
                    output.flush()
                    os.fsync(output.fileno())
                extracted.append(target)
        except Exception:
            shutil.rmtree(destination, ignore_errors=True)
            raise
        return extracted


def _normalize_member_name(name: str) -> str:
    path = PurePosixPath(name)
    if (
        not name
        or path.is_absolute()
        or any(part in {"", ".", ".."} for part in path.parts)
        or "\\" in name
        or "\x00" in name
    ):
        raise ArchiveSecurityError(f"Unsafe archive path: {name!r}")
    return path.as_posix()


def _require_within_destination(destination: Path, target: Path) -> None:
    try:
        target.resolve().relative_to(destination.resolve())
    except ValueError as exc:
        raise ArchiveSecurityError("Archive path escapes destination") from exc
