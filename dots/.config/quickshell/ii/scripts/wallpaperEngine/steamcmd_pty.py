"""Runs steamcmd on a pty shared by download.py and login.py."""
import fcntl
import os
import pty
import signal
import subprocess
import termios


def _take_terminal():
    # The pty becomes steamcmd's controlling terminal, so prompts that read
    # /dev/tty instead of stdin get our input as well
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)


def spawn(command):
    """Starts steamcmd in its own session with the pty as its terminal.
    A pty also makes it flush progress lines instead of block-buffering them.
    Returns (process, master fd)."""
    master, slave = pty.openpty()
    attrs = termios.tcgetattr(slave)
    attrs[3] &= ~termios.ECHO  # Never echo the password back into the output
    termios.tcsetattr(slave, termios.TCSANOW, attrs)
    try:
        process = subprocess.Popen(
            command, stdin=slave, stdout=slave, stderr=slave,
            close_fds=True, start_new_session=True, preexec_fn=_take_terminal,
        )
    except BaseException:
        os.close(master)
        raise
    finally:
        os.close(slave)
    return process, master


def kill_tree(process):
    """steamcmd.sh runs the real binary as a child, so kill the whole session."""
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass
