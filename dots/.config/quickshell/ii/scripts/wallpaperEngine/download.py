#!/usr/bin/env python3
"""
Downloads a Wallpaper Engine "Video" wallpaper from the Steam Workshop with
steamcmd and copies its video file into the target directory.

Login uses the session steamcmd cached on the last sign-in (steamLogin.qml), so
no Steam Guard confirmation is needed. Only when that cache is missing does it
fall back to the password from the keyring:
    secret-tool store --label="Steam (steamcmd)" application illogical-impulse-steam account <user>
which is typed into steamcmd's password prompt, never put on the command line
or in a file. A password login starts a new session and may need Steam Guard again.

Output (one event per line, consumed by services/WallpaperEngine.qml):
    STATUS <login|confirm|downloading|copying>
    PROGRESS <done>/<total>
    DONE <absolute path of the copied video>
    ERROR <guard|auth|steamcmd|notfound|notvideo|usage> <message>
"""
import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys

from steamcmd_pty import kill_tree, spawn

APP_ID = 431960
VIDEO_EXTENSIONS = (".mp4", ".mkv", ".webm", ".mov")
# Only used when steamcmd's output has no "Downloaded item ... to" line; steamcmd's
# own folder goes first, the Steam client's ones are never deleted
STEAMCMD_WORKSHOP_DIR = os.path.expanduser(f"~/.steam/steamcmd/steamapps/workshop/content/{APP_ID}")
WORKSHOP_DIRS = [
    STEAMCMD_WORKSHOP_DIR,
    os.path.expanduser(f"~/.local/share/Steam/steamapps/workshop/content/{APP_ID}"),
    os.path.expanduser(f"~/Steam/steamapps/workshop/content/{APP_ID}"),
    os.path.expanduser(f"~/.steam/steam/steamapps/workshop/content/{APP_ID}"),
]
PROGRESS_RE = re.compile(r"downloading\s+\((\d+)\s*/\s*(\d+)\)", re.IGNORECASE)
DOWNLOADED_RE = re.compile(r'downloaded item (\d+) to "([^"]+)"', re.IGNORECASE)
GUARD_MARKERS = ("steam guard code", "two-factor code", "two factor code")
PASSWORD_PROMPT = "password:"
AUTH_MARKERS = ("invalid password", "login failure")


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
    """Yields lines from a pty; steamcmd redraws progress with \\r. Prompts end
    without a newline, so an unfinished line that is a prompt is yielded too."""
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
        pending = buffer.decode(errors="replace").lower()
        if PASSWORD_PROMPT in pending or any(m in pending for m in GUARD_MARKERS):
            yield buffer.decode(errors="replace").strip()
            buffer = b""
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


def download(steamcmd, user, item_id):
    """Returns the item folder steamcmd reported, or None if it printed none."""
    emit("STATUS", "login")
    try:
        process, master = spawn([steamcmd, "+login", user, "+workshop_download_item", str(APP_ID), item_id, "validate", "+quit"])
    except FileNotFoundError:
        fail("steamcmd", f"'{steamcmd}' not found")

    def on_cancel(*_):
        kill_tree(process)
        sys.exit(143)
    signal.signal(signal.SIGTERM, on_cancel)

    def abort(code, message):
        kill_tree(process)
        fail(code, message)

    try:
        item_dir = read_output(master, user, item_id, abort)
    finally:
        os.close(master)
    if process.wait() != 0:
        fail("steamcmd", f"steamcmd exited with code {process.returncode}")
    return item_dir


def read_output(master, user, item_id, abort):
    last_progress = None
    password_sent = False
    item_dir = None
    for line in read_lines(master):
        lower = line.lower()
        if any(m in lower for m in GUARD_MARKERS):
            abort("guard", "Steam Guard code required; sign in through steamLogin.qml")
        if PASSWORD_PROMPT in lower:
            # The cached session is missing or expired
            password = None if password_sent else keyring_password(user)
            if not password:
                abort("auth", "Steam login failed" if password_sent else "No cached steamcmd session and no password in the keyring")
            os.write(master, (password + "\n").encode())
            password_sent = True
            continue
        if any(m in lower for m in AUTH_MARKERS):
            abort("auth", "Steam login failed: wrong keyring password")
        if "please confirm the login in the steam mobile app" in lower:
            emit("STATUS", "confirm")
        if "downloading item" in lower:
            emit("STATUS", "downloading")
        match = PROGRESS_RE.search(line)
        if match and match.groups() != last_progress:
            last_progress = match.groups()
            emit("PROGRESS", f"{match.group(1)}/{match.group(2)}")
        match = DOWNLOADED_RE.search(line)
        if match and match.group(1) == item_id:
            item_dir = match.group(2)
        if "error!" in lower:
            abort("steamcmd", line)
    return item_dir


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
    parser.add_argument("--target-dir", default="~/Pictures/Wallpapers/Animated")
    parser.add_argument("--steamcmd", default="steamcmd")
    parser.add_argument("--keep-cache", action="store_true", help="Keep the copy in steamapps/workshop")
    args = parser.parse_args()

    item_id = parse_workshop_id(args.item)
    if not item_id:
        fail("usage", f"Not a Workshop URL or ID: {args.item}")

    target_dir = os.path.abspath(os.path.expanduser(args.target_dir))

    item_dir = download(args.steamcmd, args.user, item_id)
    # Only delete what steamcmd itself downloaded, never the Steam client's copy
    removable = item_dir is not None
    if item_dir is None or not os.path.isdir(item_dir):
        item_dir = next((os.path.join(d, item_id) for d in WORKSHOP_DIRS if os.path.isdir(os.path.join(d, item_id))), None)
        removable = item_dir is not None and os.path.dirname(item_dir) == STEAMCMD_WORKSHOP_DIR
    if not item_dir:
        fail("notfound", f"Downloaded item {item_id} not found in Steam workshop directories")

    video = find_video(item_dir)
    if not video:
        fail("notvideo", f"Item {item_id} has no video file (probably a Scene or Web wallpaper)")

    emit("STATUS", "copying")
    os.makedirs(target_dir, exist_ok=True)
    destination = os.path.join(target_dir, f"wallpaper_{item_id}{os.path.splitext(video)[1].lower()}")
    tmp = destination + ".part"
    shutil.copyfile(video, tmp)
    os.replace(tmp, destination)
    if removable and not args.keep_cache:
        shutil.rmtree(item_dir, ignore_errors=True)
    emit("DONE", destination)


if __name__ == "__main__":
    main()
