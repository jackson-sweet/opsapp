#!/usr/bin/env python3
"""Host-side screen capture bridge for SiteVisitTypeSettingsKeyboardTests.

The suite's two visual tests prove the software keyboard's DONE with the
simulator's real composited pixels. An app-hosted XCTest cannot capture those
itself: `drawHierarchy` omits the remote keyboard, and `XCUIScreen` is refused
without UI-testing authority. This bridge takes the pictures from the host with
`xcrun simctl io <udid> screenshot` when a test asks for one.

Run it from the ops-ios checkout BEFORE the suite, against the booted simulator
the tests will use, and wait for its `"ready": true` line:

    python3 scripts/testing/capture_keyboard_screens.py --udid <UDID> --max-seconds 600

then, in another shell:

    xcodebuild test-without-building ... \
        -only-testing:OPSTests/SiteVisitTypeSettingsKeyboardTests

While it runs, the bridge keeps a heartbeat file (`capture-bridge.json`) in the
app's capture cache, refreshed about once a second and removed on exit. The two
visual tests read it before doing any work: no fresh heartbeat for their
simulator means they skip with this command, never fail on the wrong cause. A
running bridge that does not answer a request is a real failure.

The bridge exits after the four distinct captures the suite makes, or at its
deadline (Python 3.9+). It captures only the explicitly selected, already
booted simulator and the OPS app's own cache requests: no launch, install,
settings change, physical device, or network access.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import time
import uuid

BUNDLE = "co.opsapp.ops.OPS"
NAMES = {
    "site-visit-type-name-keyboard", "site-visit-type-name-after-done",
    "site-visit-checklist-field-label-keyboard", "site-visit-checklist-field-label-after-done",
}
# Read by SiteVisitTypeSettingsKeyboardTests.requireCaptureBridge(). Keep the
# file name and keys in step with that test.
HEARTBEAT = "capture-bridge.json"


def simctl(*args):
    return subprocess.run(["xcrun", "simctl", *args], check=True, capture_output=True, text=True, timeout=15).stdout.strip()


def capture_cache(udid):
    container = Path(simctl("get_app_container", udid, BUNDLE, "data")).resolve(strict=True)
    if udid not in {p.upper() for p in container.parts} or container.parent.name != "Application":
        raise RuntimeError("Unexpected simulator app data container")
    cache = container / "Library" / "Caches" / "OPSKeyboardScreenshotProof"
    if cache.is_symlink() or not cache.resolve().is_relative_to(container):
        raise RuntimeError("Capture cache must stay inside the selected app container")
    cache.mkdir(parents=True, exist_ok=True)
    return cache


def write_heartbeat(cache, udid, started, expires):
    """Atomically replace the heartbeat the tests check before they start."""
    beat = cache / HEARTBEAT
    temporary = cache / f"{HEARTBEAT}.tmp"
    if beat.is_symlink() or temporary.is_symlink():
        raise RuntimeError("The capture bridge heartbeat must not be a symlink")
    temporary.write_text(json.dumps({
        "simulatorUDID": udid, "bundleID": BUNDLE, "pid": os.getpid(),
        "startedAt": started, "heartbeatAt": time.time(), "expiresAt": expires,
    }))
    os.replace(temporary, beat)


def remove_heartbeat(cache):
    """A stopped bridge must never look alive to the next test run."""
    if cache is None:
        return
    for leftover in (cache / HEARTBEAT, cache / f"{HEARTBEAT}.tmp"):
        try:
            if leftover.is_symlink() or leftover.is_file():
                leftover.unlink()
        except OSError:
            pass


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--udid", required=True, help="Explicitly owned, already booted simulator UUID")
    parser.add_argument("--max-seconds", type=int, default=180, choices=range(1, 601), metavar="1..600")
    args = parser.parse_args()
    udid = str(uuid.UUID(args.udid)).upper()
    devices = json.loads(simctl("list", "devices", "booted", "-j"))["devices"]
    if not any(d["udid"].upper() == udid and d["state"] == "Booted" for group in devices.values() for d in group):
        raise RuntimeError("The selected simulator is not booted")
    started = time.time()
    expires = started + args.max_seconds
    deadline = time.monotonic() + args.max_seconds
    seen, completed = set(), set()
    cache, next_resolution = None, 0
    try:
        while time.monotonic() < deadline:
            # Xcode replaces the app data container when installing the test host.
            # Follow only this exact simulator/bundle binding, retaining the original
            # freshness boundary. The temporary uninstall gap is a bounded retry.
            if time.monotonic() >= next_resolution:
                try:
                    current_cache = capture_cache(udid)
                except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
                    cache = None
                else:
                    if current_cache != cache:
                        remove_heartbeat(cache)
                        print(json.dumps({"ready": True, "simulator": udid, "cache": str(current_cache)}), flush=True)
                    cache = current_cache
                    try:
                        write_heartbeat(cache, udid, started, expires)
                    except FileNotFoundError:
                        # Installation retired the container between resolution and write.
                        cache = None
                next_resolution = time.monotonic() + 1
            if cache is None:
                time.sleep(0.1)
                continue
            for request_file in cache.glob("*.request.json"):
                if request_file.name in seen:
                    continue
                try:
                    if request_file.is_symlink() or request_file.stat().st_size > 4096:
                        raise RuntimeError("Invalid screenshot request file")
                    request = json.loads(request_file.read_text())
                except FileNotFoundError:
                    # Installation may retire a listed file before its read.
                    cache, next_resolution = None, 0
                    break
                request_id = str(uuid.UUID(request["requestID"]))
                requested_at = request["requestedAt"]
                if request_file.name != f"{request_id}.request.json":
                    raise RuntimeError("Screenshot request filename must match its UUID")
                if not isinstance(requested_at, (int, float)) or not math.isfinite(requested_at):
                    raise RuntimeError("Invalid screenshot request timestamp")
                seen.add(request_file.name)
                if requested_at < started or not 0 <= time.time() - requested_at <= 20:
                    continue  # Old cache evidence is never acknowledged as a new capture.
                if request["name"] not in NAMES or request["bundleID"] != BUNDLE or request["simulatorUDID"].upper() != udid:
                    raise RuntimeError("Request does not match the selected app, simulator, and capture stage")
                png = cache / f"{request_id}.png"
                temporary = cache / f"{request_id}.capture.png"
                ack = cache / f"{request_id}.ack.json"
                ack_temporary = cache / f"{request_id}.ack.tmp"
                if any(p.exists() or p.is_symlink() for p in (png, temporary, ack, ack_temporary)):
                    raise RuntimeError("A fresh screenshot UUID must not reuse existing output")
                reply = {"requestID": request_id, "name": request["name"], "bundleID": BUNDLE,
                         "simulatorUDID": udid, "captureStartedAt": time.time(), "sha256": None, "error": None}
                try:
                    simctl("io", udid, "screenshot", "--type=png", str(temporary))
                    data = temporary.read_bytes()
                    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
                        raise RuntimeError("simctl did not produce PNG bytes")
                    os.replace(temporary, png)
                    reply["sha256"] = hashlib.sha256(data).hexdigest()
                except Exception as error:
                    reply["error"] = str(error)[:1000]
                reply["completedAt"] = time.time()
                ack_temporary.write_text(json.dumps(reply))
                os.replace(ack_temporary, ack)
                print(json.dumps(reply), flush=True)
                if reply["error"]:
                    raise RuntimeError(reply["error"])
                completed.add(request["name"])
                if completed == NAMES:
                    return
            time.sleep(0.1)
        raise TimeoutError(f"Capture deadline expired: received {sorted(completed)}")
    finally:
        remove_heartbeat(cache)


if __name__ == "__main__":
    main()
