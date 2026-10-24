#!/usr/bin/env python3
"""
Interactive steamcmd login for steamLogin.qml. On success steamcmd caches the
session, and the password can be saved to the keyring for download.py.

Input (stdin, one per line):
    <password>            first line
    CODE <steam guard>    when asked for a code
    CANCEL
Output (one event per line):
    STATUS <connecting|checking>
    NEED_CODE <email|mobile>
    CODE_INVALID
    CONFIRM                approve the login in the Steam Mobile app
    DONE
    ERROR <password|ratelimit|steamcmd> <message>
"""
import argparse
import os
import pty
import re
import select
import subprocess
import sys
import tempfile

ANSI_RE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
# Prompts end without a newline, so they are matched against the unfinished line too
PROMPTS = {
    "steam guard code:": ("NEED_CODE", "email"),
    "two-factor code:": ("NEED_CODE", "mobile"),
}
EVENTS = [
    ("please confirm the login in the steam mobile app", ("CONFIRM",)),
    ("that steam guard code was invalid", ("CODE_INVALID",)),
    ("two-factor code mismatch", ("CODE_INVALID",)),
    ("invalid login auth code", ("CODE_INVALID",)),
    ("invalid password", ("ERROR", "password", "Wrong account name or password")),
    ("rate limit exceeded", ("ERROR", "ratelimit", "Too many login attempts, try again later")),
    ("waiting for user info...ok", ("DONE",)),
]


def emit(*parts):
    print(" ".join(str(p) for p in parts), flush=True)


def quote(value):
    return '"' + value.replace('"', '\\"') + '"'


def store_password(user, password):
    subprocess.run(
        ["secret-tool", "store", "--label=Steam (steamcmd)", "application", "illogical-impulse-steam", "account", user],
        input=password, text=True, check=False,
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--user", required=True)
    parser.add_argument("--remember", action="store_true", help="Save the password to the keyring on success")
    parser.add_argument("--steamcmd", default="steamcmd")
    args = parser.parse_args()

    password = sys.stdin.readline().rstrip("\n")
    if not password:
        emit("ERROR", "password", "Empty password")
        return 1

    fd, runscript = tempfile.mkstemp(prefix="steamcmd-login-", suffix=".txt", dir=os.environ.get("XDG_RUNTIME_DIR"))
    with os.fdopen(fd, "w") as f:  # mkstemp creates it with mode 600
        f.write(f"login {quote(args.user)} {quote(password)}\nquit\n")

    emit("STATUS", "connecting")
    master, slave = pty.openpty()
    try:
        process = subprocess.Popen([args.steamcmd, "+runscript", runscript], stdin=slave, stdout=slave, stderr=slave, close_fds=True)
    except FileNotFoundError:
        os.remove(runscript)
        emit("ERROR", "steamcmd", f"'{args.steamcmd}' not found")
        return 1
    finally:
        os.close(slave)

    result = None
    buffer = ""
    stdin_open = True
    try:
        while result is None:
            readable, _, _ = select.select([master] + ([sys.stdin] if stdin_open else []), [], [])
            if sys.stdin in readable:
                line = sys.stdin.readline()
                if not line or line.strip() == "CANCEL":
                    stdin_open = False
                    process.kill()
                    break
                if line.startswith("CODE "):
                    emit("STATUS", "checking")
                    os.write(master, (line[5:].strip() + "\n").encode())
            if master in readable:
                try:
                    chunk = os.read(master, 4096)
                except OSError:  # EIO once steamcmd exits
                    chunk = b""
                if not chunk:
                    break
                buffer += ANSI_RE.sub("", chunk.decode(errors="replace"))
                *lines, buffer = re.split(r"[\r\n]", buffer)
                for line in lines:
                    lower = line.lower()
                    for marker, event in EVENTS:
                        if marker in lower and result is None:
                            if event[0] in ("DONE", "ERROR"):
                                result = event
                            else:
                                emit(*event)
                for marker, event in PROMPTS.items():
                    if marker in buffer.lower():
                        emit(*event)
                        buffer = ""
    finally:
        os.remove(runscript)

    try:
        return finish(process, master, result, stdin_open, args, password)
    finally:
        os.close(master)


def finish(process, master, result, stdin_open, args, password):
    if result and result[0] == "DONE":
        # Keep reading so steamcmd never blocks on a full pty while it quits
        while True:
            try:
                if not os.read(master, 4096):
                    break
            except OSError:
                break
        process.wait()
        if args.remember:
            store_password(args.user, password)
        emit("DONE")
        return 0
    process.kill()
    process.wait()
    if result:
        emit(*result)
    elif stdin_open:
        emit("ERROR", "steamcmd", f"steamcmd exited with code {process.returncode}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
