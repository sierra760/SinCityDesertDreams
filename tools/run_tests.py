#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Run the headless Godot test suite.

Every game/tests/test_*.gd file is run in its own Godot process. A file passes
only when it prints a final "Results: N passed, 0 failed" line and the engine
reports no engine/script/resource diagnostics and exits successfully.

Usage: python3 tools/run_tests.py [--no-import] [--shard K/N] [pattern ...]
Set GODOT to point at the engine binary if it is not on PATH. The project is
copied to a temporary test project with unique user data, then imported and run.
Only the copied project's custom user-data directory setting changes; player
saves/preferences and the source project are untouched. The project copy is
removed on exit. TEST_LOG_DIR can retain logs outside that temporary copy.

Advanced: TEST_GAME_PATH selects a caller-owned isolated project instead. The
caller must ensure its user data cannot reference a player's saves/preferences;
this override is neither copied nor removed. Only this override supports
--no-import; a fresh default copy always requires import. TEST_TIMEOUT overrides
the per-file timeout (600 seconds by default for real-time traversal fixtures).
--shard K/N runs every Nth matching file starting with the Kth (1-based), so N
CI runners can split the suite between them.
"""

from __future__ import annotations

from contextlib import contextmanager
from collections.abc import Iterator
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

try:
    import fcntl
except ImportError:  # Windows
    fcntl = None
    import msvcrt

ROOT = Path(__file__).resolve().parent.parent
GAME = Path(os.environ.get("TEST_GAME_PATH", str(ROOT / "game"))).resolve()
RESULTS = re.compile(r"^Results: (\d+) passed, (\d+) failed\s*$", re.M)
ENGINE_ERROR = re.compile(r"Unicode parsing error|SCRIPT ERROR:|Parse Error:|Compile Error:|(?:^|\n)(?:ERROR|WARNING):|ObjectDB instances leaked|resources still in use", re.I)


@contextmanager
def isolated_test_project(source: Path) -> Iterator[Path]:
    """Yield a source-identical temporary project with private test user data.

    Skip only regenerable top-level editor caches and local exports. Authored
    files in nested directories named export remain part of the project.
    """
    source = source.resolve()

    def ignore(directory: str, names: list[str]) -> list[str]:
        return [name for name in names if name in {".godot", "export"}] if Path(directory) == source else []

    with tempfile.TemporaryDirectory(prefix="sincity-tests-") as temporary:
        project = Path(temporary) / "game"
        shutil.copytree(source, project, ignore=ignore)
        settings_path = project / "project.godot"
        settings = settings_path.read_bytes().decode("utf-8")
        # Refuse an unexpected project shape rather than allowing Godot to fall
        # back to the ordinary application user-data directory.
        if not re.search(r"(?m)^config/use_custom_user_dir=true[ \t]*\r?$", settings):
            raise ValueError("Test isolation requires config/use_custom_user_dir=true")
        private_name = "SinCityDesertDreamsTests-" + Path(temporary).name
        settings, count = re.subn(r'(?m)^(config/custom_user_dir_name=)"[^"\r\n]*"',
                                 lambda match: match.group(1) + '"' + private_name + '"', settings)
        if count != 1:
            raise ValueError("Test isolation requires one custom user-data directory setting")
        settings_path.write_bytes(settings.encode("utf-8"))
        yield project


def classify_output(returncode: int, output: str) -> tuple[bool, str]:
    if returncode != 0:
        return False, f"exit {returncode}"
    if ENGINE_ERROR.search(output):
        return False, "engine/script/resource diagnostic"
    summaries = list(RESULTS.finditer(output))
    if not summaries:
        return False, "missing results line"
    if any(int(m.group(2)) != 0 for m in summaries):
        return False, "failed assertions"
    if int(summaries[-1].group(1)) == 0:
        return False, "no tests executed"
    return True, "clean"


def retain_output(name: str, output: str) -> None:
    destination = os.environ.get("TEST_LOG_DIR")
    if destination:
        directory = Path(destination)
        directory.mkdir(parents=True, exist_ok=True)
        (directory / name).write_text(output, encoding="utf-8")


def engine_log(name: str) -> list[str]:
    directory = Path(os.environ.get("TEST_LOG_DIR", str(GAME / ".godot" / "test-logs"))).resolve()
    directory.mkdir(parents=True, exist_ok=True)
    return ["--log-file", str(directory / (name + "-engine.log"))]


def timeout_output(exc: subprocess.TimeoutExpired) -> str:
    def decode(raw: str | bytes | None) -> str:
        return raw.decode(errors="replace") if isinstance(raw, bytes) else (raw or "")
    return decode(exc.stdout) + decode(exc.stderr) + "\n[timeout]"


def run_engine(cmd: list[str], timeout: int) -> subprocess.CompletedProcess[str]:
    # The engine prints UTF-8 whatever the host locale; Windows defaults to a
    # legacy code page that cannot decode it.
    return subprocess.run(cmd, capture_output=True, encoding="utf-8", errors="replace", timeout=timeout)


def lock_exclusive(lock) -> None:
    if fcntl is not None:
        fcntl.flock(lock, fcntl.LOCK_EX)
        return
    while True:
        try:
            msvcrt.locking(lock.fileno(), msvcrt.LK_LOCK, 1)
            return
        except OSError:
            # LK_LOCK gives up after ten seconds; keep waiting like flock.
            continue


def find_godot() -> str:
    def usable(path: str) -> bool:
        try:
            # The first Rosetta launch can spend over ten seconds translating
            # a newly installed universal editor before it reports its version.
            version = subprocess.run([path, "--version"], capture_output=True, text=True, timeout=60)
        except (OSError, subprocess.TimeoutExpired):
            return False
        match = re.match(r"^(\d+)\.(\d+)(?:\.(\d+))?\.stable\.", version.stdout.strip())
        return version.returncode == 0 and match is not None and tuple(int(part or 0) for part in match.groups()) >= (4, 7, 2)

    env = os.environ.get("GODOT")
    if env:
        if usable(env):
            return env
        sys.exit("Godot 4.7.2 or newer stable is required; GODOT points to an incompatible or unavailable engine")
    for name in ("godot", "godot4", "Godot"):
        path = shutil.which(name)
        if path and usable(path):
            return path
    mac = "/Applications/Godot.app/Contents/MacOS/Godot"
    if Path(mac).exists() and usable(mac):
        return mac
    sys.exit("Godot 4.7.2 or newer stable not found; set GODOT=/path/to/godot")


def refresh_class_cache(godot: str) -> None:
    """Rescan the project so new class_name declarations resolve headless.

    The engine only rebuilds its global class cache during an editor scan, so
    a fresh script with a class_name is invisible to `-s` runs until then. The
    scan takes a couple of seconds; a file lock keeps concurrent runners from
    scanning at the same time.
    """
    lock_path = GAME / ".godot" / "run_tests.lock"
    lock_path.parent.mkdir(exist_ok=True)
    with open(lock_path, "w") as lock:
        lock_exclusive(lock)
        try:
            proc = run_engine([godot, "--headless", "--audio-driver", "Dummy", "--path", str(GAME), "--import"] + engine_log("import"), 600)
        except subprocess.TimeoutExpired as exc:
            out = timeout_output(exc)
            retain_output("import.log", out)
            raise RuntimeError("Godot import timed out:\n" + out) from exc
        out = (proc.stdout or "") + (proc.stderr or "")
        retain_output("import.log", out)
        if proc.returncode != 0 or ENGINE_ERROR.search(out):
            raise RuntimeError("Godot import failed:\n" + out)


def run_one(godot: str, test: Path, timeout: int) -> tuple[bool, str]:
    cmd = [godot, "--headless", "--audio-driver", "Dummy", "--path", str(GAME), "-s", "res://tests/" + test.name] + engine_log(test.stem)
    try:
        proc = run_engine(cmd, timeout)
    except subprocess.TimeoutExpired as exc:
        out = timeout_output(exc)
        retain_output(test.stem + ".log", out)
        return False, out
    out = (proc.stdout or "") + (proc.stderr or "")
    retain_output(test.stem + ".log", out)
    ok, _reason = classify_output(proc.returncode, out)
    return ok, out


def parse_shard(argv: list[str]) -> tuple[list[str], tuple[int, int] | None]:
    """Remove a --shard K/N (or --shard=K/N) option from argv."""
    rest: list[str] = []
    shard: tuple[int, int] | None = None
    values = iter(argv)
    for arg in values:
        if arg == "--shard" or arg.startswith("--shard="):
            value = arg.partition("=")[2] if "=" in arg else next(values, "")
            match = re.fullmatch(r"(\d+)/(\d+)", value)
            if not match or not 1 <= int(match.group(1)) <= int(match.group(2)):
                raise ValueError(f"--shard needs K/N with 1 <= K <= N, not {value!r}")
            shard = (int(match.group(1)), int(match.group(2)))
        else:
            rest.append(arg)
    return rest, shard


def _run_suite(godot: str, argv: list[str]) -> int:
    argv, shard = parse_shard(argv)
    if "--no-import" in argv:
        argv = [a for a in argv if a != "--no-import"]
    else:
        try:
            refresh_class_cache(godot)
        except (RuntimeError, subprocess.TimeoutExpired) as exc:
            print(str(exc), file=sys.stderr)
            return 1
    patterns = argv or ["test_*.gd"]
    tests: list[Path] = []
    for pattern in patterns:
        if not pattern.endswith(".gd"):
            pattern = f"*{pattern}*.gd"
        tests.extend(sorted((GAME / "tests").glob(pattern)))
    tests = sorted(set(t for t in tests if t.name.startswith("test_") and t.name != "test_case.gd"))
    if shard:
        tests = tests[shard[0] - 1::shard[1]]
    if not tests:
        print("no tests matched")
        return 1
    timeout = int(os.environ.get("TEST_TIMEOUT", "600"))
    failures = 0
    started = time.time()
    for test in tests:
        ok, out = run_one(godot, test, timeout)
        status = "ok  " if ok else "FAIL"
        m = RESULTS.search(out)
        summary = f"{m.group(1)}/{m.group(2)}" if m else "no results line"
        print(f"{status} {test.name} ({summary})")
        if not ok:
            failures += 1
            print(out.strip()[-4000:])
    print(f"\n{len(tests) - failures}/{len(tests)} files passed in {time.time() - started:.1f}s")
    return 1 if failures else 0


def main(argv: list[str]) -> int:
    global GAME
    godot = find_godot()
    original_game = GAME
    override = os.environ.get("TEST_GAME_PATH")
    try:
        if override:
            GAME = Path(override).resolve()
            return _run_suite(godot, argv)
        with isolated_test_project(original_game) as project:
            GAME = project
            # The default copy excludes its regenerable cache, so it must be
            # imported even when a caller supplied the advanced skip flag.
            return _run_suite(godot, [arg for arg in argv if arg != "--no-import"])
    except (OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    finally:
        GAME = original_game


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
