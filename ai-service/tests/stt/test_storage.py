import os
import time

from api.services.stt.ring_buffer import AudioRingBuffer
from api.services.stt.temp_audio_writer import TempAudioWriter, cleanup_stale_audio


def test_ring_buffer_remains_bounded():
    ring = AudioRingBuffer(8)
    ring.append(b"123456")
    ring.append(b"7890")
    assert len(ring) == 8
    assert ring.getvalue() == b"34567890"


def test_temp_writer_rotates_and_cleans(tmp_path):
    writer = TempAudioWriter(str(tmp_path), "s1", max_file_bytes=4, max_files=2)
    writer.write(b"1234")
    writer.write(b"56")
    writer.write(b"7890")
    paths = writer.paths
    assert len(paths) == 2
    writer.close(delete=False)
    old = time.time() - 120
    for path in paths:
        os.utime(path, (old, old))
    assert cleanup_stale_audio(str(tmp_path), 60) == 2
