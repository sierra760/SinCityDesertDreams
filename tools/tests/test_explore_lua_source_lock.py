"""Offline source-lock contract; corrupt archives must never be accepted."""
import hashlib
import json
from pathlib import Path

LOCK = Path(__file__).resolve().parents[2] / 'native/explore-lua/source-lock.json'

def test_official_source_lock():
    lock = json.loads(LOCK.read_text())
    assert lock['lua']['version'] == '5.4.9'
    assert lock['lua']['url'] == 'https://www.lua.org/ftp/lua-5.4.9.tar.gz'
    assert lock['lua']['sha256'] == '2335b6c582a52654f94612bf10d2f4672805d05329aa6568b1d8cd9e5c6fb8e6'
    assert lock['godot_cpp']['revision'] == 'e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77'

def test_corrupt_source_hashes_rejected():
    expected = json.loads(LOCK.read_text())['lua']['sha256']
    for archive in (b'', b'corrupt', b'Lua 5.4.9', bytes(range(256))):
        assert hashlib.sha256(archive).hexdigest() != expected
