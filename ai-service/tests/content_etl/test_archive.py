from __future__ import annotations

import io
import tarfile

import pytest

from api.services.content_etl.archive import (
    ArchiveLimits,
    ArchiveSecurityError,
    safe_extract_tar,
)


def _write_tar(path, members: list[tuple[tarfile.TarInfo, bytes]]) -> None:
    with tarfile.open(path, "w:gz") as archive:
        for info, content in members:
            if info.isfile():
                info.size = len(content)
                archive.addfile(info, io.BytesIO(content))
            else:
                archive.addfile(info)


def _file(name: str, content: bytes = b"data") -> tuple[tarfile.TarInfo, bytes]:
    return tarfile.TarInfo(name), content


def test_safe_extract_writes_only_requested_members(tmp_path):
    archive_path = tmp_path / "dataset.tar.gz"
    _write_tar(
        archive_path,
        [
            _file("dataset/records.tsv", b"records"),
            _file("dataset/README", b"readme"),
        ],
    )

    extracted = safe_extract_tar(
        archive_path,
        tmp_path / "out",
        requested_members={"dataset/records.tsv"},
    )

    assert extracted == [tmp_path / "out" / "dataset" / "records.tsv"]
    assert extracted[0].read_bytes() == b"records"
    assert not (tmp_path / "out" / "dataset" / "README").exists()


@pytest.mark.parametrize("member_name", ["/etc/passwd", "../escape", "a/../../b"])
def test_safe_extract_rejects_absolute_and_parent_paths_before_writing(
    tmp_path,
    member_name,
):
    archive_path = tmp_path / "unsafe.tar.gz"
    _write_tar(
        archive_path,
        [
            _file("safe/records.tsv"),
            _file(member_name),
        ],
    )

    with pytest.raises(ArchiveSecurityError, match="path"):
        safe_extract_tar(
            archive_path,
            tmp_path / "out",
            requested_members={"safe/records.tsv"},
        )

    assert not (tmp_path / "out").exists()


@pytest.mark.parametrize("link_type", [tarfile.SYMTYPE, tarfile.LNKTYPE])
def test_safe_extract_rejects_symbolic_and_hard_links(tmp_path, link_type):
    archive_path = tmp_path / "links.tar.gz"
    link = tarfile.TarInfo("dataset/link")
    link.type = link_type
    link.linkname = "../../outside"
    _write_tar(archive_path, [(link, b"")])

    with pytest.raises(ArchiveSecurityError, match="links"):
        safe_extract_tar(
            archive_path,
            tmp_path / "out",
            requested_members={"dataset/link"},
        )


def test_safe_extract_enforces_file_count_individual_and_total_limits(tmp_path):
    count_archive = tmp_path / "count.tar.gz"
    _write_tar(count_archive, [_file("a"), _file("b")])
    with pytest.raises(ArchiveSecurityError, match="file-count"):
        safe_extract_tar(
            count_archive,
            tmp_path / "count-out",
            requested_members={"a"},
            limits=ArchiveLimits(max_files=1, max_file_bytes=10, max_total_bytes=10),
        )

    size_archive = tmp_path / "size.tar.gz"
    _write_tar(size_archive, [_file("a", b"123456")])
    with pytest.raises(ArchiveSecurityError, match="per-file"):
        safe_extract_tar(
            size_archive,
            tmp_path / "size-out",
            requested_members={"a"},
            limits=ArchiveLimits(max_files=2, max_file_bytes=5, max_total_bytes=10),
        )

    total_archive = tmp_path / "total.tar.gz"
    _write_tar(total_archive, [_file("a", b"1234"), _file("b", b"5678")])
    with pytest.raises(ArchiveSecurityError, match="total"):
        safe_extract_tar(
            total_archive,
            tmp_path / "total-out",
            requested_members={"a", "b"},
            limits=ArchiveLimits(max_files=2, max_file_bytes=5, max_total_bytes=7),
        )


def test_safe_extract_rejects_duplicate_member_names(tmp_path):
    archive_path = tmp_path / "duplicate.tar.gz"
    _write_tar(archive_path, [_file("records.tsv"), _file("records.tsv")])

    with pytest.raises(ArchiveSecurityError, match="duplicate"):
        safe_extract_tar(
            archive_path,
            tmp_path / "out",
            requested_members={"records.tsv"},
        )
