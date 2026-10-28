"""The forget-vs-in-flight-save race, against a real mongod.

A mock cannot say whether `$or` + upsert + the unique index behave as the guard
assumes, so this starts a throwaway mongod and skips when none is installed.
"""

import asyncio
import shutil
import socket
import subprocess
import time
from datetime import datetime, timedelta, timezone

import pytest
import pytest_asyncio
from motor.motor_asyncio import AsyncIOMotorClient

from api.services import lexi_memory

pytestmark = pytest.mark.skipif(
    shutil.which("mongod") is None, reason="mongod not installed"
)


@pytest.fixture(scope="module")
def mongo_uri(tmp_path_factory):
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    proc = subprocess.Popen(
        [
            "mongod", "--dbpath", str(tmp_path_factory.mktemp("mongo")),
            "--port", str(port), "--bind_ip", "127.0.0.1",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    deadline = time.time() + 30
    while time.time() < deadline:
        with socket.socket() as sock:
            if sock.connect_ex(("127.0.0.1", port)) == 0:
                break
        time.sleep(0.2)
    else:
        proc.kill()
        pytest.skip("mongod did not start")
    yield f"mongodb://127.0.0.1:{port}"
    proc.terminate()
    proc.wait(timeout=20)


@pytest_asyncio.fixture
async def db(mongo_uri):
    client = AsyncIOMotorClient(mongo_uri)
    database = client["lexi_memory_test"]
    await database[lexi_memory.COLLECTION].drop()
    await database[lexi_memory.COLLECTION].create_index("user_id", unique=True)
    yield database
    client.close()


def _ago(seconds: float) -> datetime:
    return datetime.now(timezone.utc) - timedelta(seconds=seconds)


@pytest.mark.asyncio
async def test_save_then_load_then_forget_all(db):
    await lexi_memory.save_facts(db, "u1", {"goal": "IELTS"}, since=_ago(1))
    assert await lexi_memory.load_facts(db, "u1") == {"goal": "IELTS"}
    assert await lexi_memory.forget_facts(db, "u1") is True
    assert await lexi_memory.load_facts(db, "u1") == {}
    assert await lexi_memory.forget_facts(db, "u1") is False


@pytest.mark.asyncio
async def test_turn_in_flight_during_forget_cannot_write_back(db):
    started = _ago(5)  # the turn began before the learner pressed forget
    await lexi_memory.save_facts(db, "u1", {"goal": "IELTS"}, since=_ago(10))
    await lexi_memory.forget_facts(db, "u1")

    await lexi_memory.save_facts(db, "u1", {"preferred_name": "Thang"}, since=started)

    assert await lexi_memory.load_facts(db, "u1") == {}
    assert await db[lexi_memory.COLLECTION].count_documents({"user_id": "u1"}) == 1


@pytest.mark.asyncio
async def test_forgetting_a_user_with_no_document_still_blocks_in_flight_turn(db):
    started = _ago(5)
    await lexi_memory.forget_facts(db, "ghost")
    await lexi_memory.save_facts(db, "ghost", {"goal": "IELTS"}, since=started)
    assert await lexi_memory.load_facts(db, "ghost") == {}


@pytest.mark.asyncio
async def test_turn_started_after_forget_saves_normally(db):
    await lexi_memory.forget_facts(db, "u1")
    await asyncio.sleep(0.01)
    await lexi_memory.save_facts(
        db, "u1", {"preferred_name": "Thang"}, since=datetime.now(timezone.utc)
    )
    assert await lexi_memory.load_facts(db, "u1") == {"preferred_name": "Thang"}


@pytest.mark.asyncio
async def test_forget_one_fact_keeps_the_others_and_blocks_in_flight_turn(db):
    await lexi_memory.save_facts(
        db, "u1", {"goal": "IELTS", "interests": "football"}, since=_ago(10)
    )
    started = _ago(5)
    await lexi_memory.forget_fact(db, "u1", "goal")
    assert await lexi_memory.load_facts(db, "u1") == {"interests": "football"}

    await lexi_memory.save_facts(db, "u1", {"goal": "IELTS"}, since=started)
    assert await lexi_memory.load_facts(db, "u1") == {"interests": "football"}


@pytest.mark.asyncio
async def test_forget_fact_rejects_unknown_key(db):
    with pytest.raises(KeyError):
        await lexi_memory.forget_fact(db, "u1", "religion")


@pytest.mark.asyncio
async def test_parallel_first_saves_leave_one_document(db):
    await asyncio.gather(
        *(
            lexi_memory.save_facts(db, "u1", {"goal": f"goal {i}"}, since=_ago(1))
            for i in range(8)
        )
    )
    assert await db[lexi_memory.COLLECTION].count_documents({"user_id": "u1"}) == 1
    assert (await lexi_memory.load_facts(db, "u1"))["goal"].startswith("goal ")
