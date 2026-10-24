#!/usr/bin/env python3
"""
Downloads a Wallpaper Engine "Video" wallpaper from the Steam Workshop with
steamcmd and copies its video file into the target directory.

Login uses the session steamcmd cached on the last sign-in (steamLogin.qml), so
no Steam Guard confirmation is needed. Only when that cache is missing does it
fall back to the password from the keyring:
    secret-tool store --label="Steam (steamcmd)" application illogical-impulse-steam account <user>
which is handed to steamcmd through a private runscript, never on the command
line. A password login starts a new session and may need Steam Guard again.

Output (one event per line, consumed by services/WallpaperEngine.qml):
    STATUS <login|confirm|downloading|copying>
    PROGRESS <done>/<total>
    DONE <absolute path of the copied video>
    ERROR <guard|auth|steamcmd|notfound|notvideo|usage> <message>
"""
import argparse
import json
import os
import pty
import re
import shutil
import signal
import subprocess
import sys
import tempfile

APP_ID = 431960
VIDEO_EXTENSIONS = (".mp4", ".mkv", ".webm", ".mov")
WORKSHOP_DIRS = [
    os.path.expanduser(f"~/.local/share/Steam/steamapps/workshop/content/{APP_ID}"),
    os.path.expanduser(f"~/Steam/steamapps/workshop/content/{APP_ID}"),
    os.path.expanduser(f"~/.steam/steam/steamapps/workshop/content/{APP_ID}"),
    os.path.expanduser(f"~/.steam/steamcmd/steamapps/workshop/content/{APP_ID}"),
]
PROGRESS_RE = re.compile(r"downloading\s+\((\d+)\s*/\s*(\d+)\)", re.IGNORECASE)
# steamcmd waits for input on these; stdin is closed, so it would fail anyway
GUARD_MARKERS = ("steam guard code", "two-factor code", "two factor code")
NO_CACHE_MARKERS = ("cached credentials not found", "cached credential is invalid")
AUTH_MARKERS = ("invalid password", "password:", "login failure")


def emit(*parts):
    print(" ".join(str(p) for p in parts), flush=True)


def fail(code, message):
    emit("ERROR", code, message)
    sys.exit(1)


def parse_workshop_id(value):
    if value.isdigit():
        return value
    match = re.search(r"[?&]id=(\d+)", value)
    return match.group(1) if match else None


def read_lines(fd):
    """Yields lines from a pty; steamcmd redraws progress with \\r."""
    buffer = b""
    while True:
        try:
            chunk = os.read(fd, 4096)
        except OSError:  # EIO once the child closes the pty
            chunk = b""
        if not chunk:
            break
        buffer += chunk
        *lines, buffer = re.split(rb"[\r\n]", buffer)
        for line in lines:
            if line.strip():
                yield line.decode(errors="replace").strip()
    if buffer.strip():
        yield buffer.decode(errors="replace").strip()


def keyring_password(user):
    try:
        result = subprocess.run(
            ["secret-tool", "lookup", "application", "illogical-impulse-steam", "account", user],
            capture_output=True, text=True, timeout=10,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result.stdout.rstrip("\n") if result.returncode == 0 and result.stdout else None


def write_runscript(user, password, item_id):
    quote = lambda s: '"' + s.replace('"', '\\"') + '"'
    fd, path = tempfile.mkstemp(prefix="steamcmd-", suffix=".txt", dir=os.environ.get("XDG_RUNTIME_DIR"))
    with os.fdopen(fd, "w") as f:  # mkstemp creates it with mode 600
        f.write(f"login {quote(user)} {quote(password)}\n")
        f.write(f"workshop_download_item {APP_ID} {item_id} validate\nquit\n")
    return path


class NoCachedSession(Exception):
    pass


def download(steamcmd, user, item_id):
    emit("STATUS", "login")
    try:
        run_steamcmd([steamcmd, "+login", user, "+workshop_download_item", str(APP_ID), item_id, "validate", "+quit"])
        return
    except NoCachedSession:
        pass
    password = keyring_password(user)
    if not password:
        fail("auth", "No cached steamcmd session and no password in the keyring")
    runscript = write_runscript(user, password, item_id)
    try:
        run_steamcmd([steamcmd, "+runscript", runscript])
    except NoCachedSession:
        fail("auth", "Steam login failed")
    finally:
        os.remove(runscript)


def run_steamcmd(command):
    # A pty makes steamcmd flush progress lines instead of block-buffering them
    master, slave = pty.openpty()
    try:
        process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=slave, stderr=slave, close_fds=True)
    except FileNotFoundError:
        fail("steamcmd", f"'{steamcmd}' not found")
    finally:
        os.close(slave)

    def on_cancel(*_):
        process.kill()
        sys.exit(143)
    signal.signal(signal.SIGTERM, on_cancel)

    try:
        read_output(process, master)
    except NoCachedSession:
        process.kill()
        process.wait()
        raise
    finally:
        os.close(master)
    if process.wait() != 0:
        fail("steamcmd", f"steamcmd exited with code {process.returncode}")


def read_output(process, master):
    last_progress = None
    for line in read_lines(master):
        lower = line.lower()
        if any(m in lower for m in NO_CACHE_MARKERS):
            raise NoCachedSession()
        if any(m in lower for m in GUARD_MARKERS):
            process.kill()
            fail("guard", "Steam Guard code required; sign in through steamLogin.qml")
        if any(m in lower for m in AUTH_MARKERS):
            process.kill()
            fail("auth", "Steam login failed: wrong keyring password")
        if "please confirm the login in the steam mobile app" in lower:
            emit("STATUS", "confirm")
        if "downloading item" in lower:
            emit("STATUS", "downloading")
        match = PROGRESS_RE.search(line)
        if match and match.groups() != last_progress:
            last_progress = match.groups()
            emit("PROGRESS", f"{match.group(1)}/{match.group(2)}")
        if "error!" in lower:
            process.kill()
            fail("steamcmd", line)


def find_video(item_dir):
    # project.json names the main file; fall back to the largest video in the item
    try:
        with open(os.path.join(item_dir, "project.json"), encoding="utf-8") as f:
            project = json.load(f)
        if str(project.get("type", "")).lower() not in ("", "video"):
            return None
        main_file = os.path.join(item_dir, project.get("file", ""))
        if main_file.lower().endswith(VIDEO_EXTENSIONS) and os.path.isfile(main_file):
            return main_file
    except (OSError, ValueError):
        pass
    videos = [
        os.path.join(root, name)
        for root, _, files in os.walk(item_dir)
        for name in files if name.lower().endswith(VIDEO_EXTENSIONS)
    ]
    return max(videos, key=os.path.getsize, default=None)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("item", help="Workshop URL or item ID")
    parser.add_argument("--user", required=True, help="Steam account name with a cached steamcmd session")
    parser.add_argument("--target-dir", default=os.path.expanduser("~/Pictures/Wallpapers/Animated"))
    parser.add_argument("--steamcmd", default="steamcmd")
    parser.add_argument("--keep-cache", action="store_true", help="Keep the copy in steamapps/workshop")
    args = parser.parse_args()

    item_id = parse_workshop_id(args.item)
    if not item_id:
        fail("usage", f"Not a Workshop URL or ID: {args.item}")

    download(args.steamcmd, args.user, item_id)

    item_dir = next((os.path.join(d, item_id) for d in WORKSHOP_DIRS if os.path.isdir(os.path.join(d, item_id))), None)
    if not item_dir:
        fail("notfound", f"Downloaded item {item_id} not found in Steam workshop directories")

    video = find_video(item_dir)
    if not video:
        fail("notvideo", f"Item {item_id} has no video file (probably a Scene or Web wallpaper)")

    emit("STATUS", "copying")
    os.makedirs(args.target_dir, exist_ok=True)
    destination = os.path.join(args.target_dir, f"wallpaper_{item_id}{os.path.splitext(video)[1].lower()}")
    tmp = destination + ".part"
    shutil.copyfile(video, tmp)
    os.replace(tmp, destination)
    if not args.keep_cache:
        shutil.rmtree(item_dir, ignore_errors=True)
    emit("DONE", destination)


if __name__ == "__main__":
    main()
