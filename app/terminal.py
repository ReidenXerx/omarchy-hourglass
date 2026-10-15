"""What runs in a terminal window: the program in the foreground of its shell, and the folder it works in.

Read from /proc for the terminal's own process tree, in small bounded pieces, never through a terminal's title (a
title says whatever the last program set it to). One shell under the terminal is needed to be sure which program is
meant; a terminal with several tabs and no way to tell which one is in front gives no label rather than a guess.
"""
from __future__ import annotations

import os
import re

NAMES = {"claude": "Claude Code", "nvim": "Neovim", "vim": "Vim", "vi": "Vim", "hx": "Helix", "helix": "Helix",
         "emacs": "Emacs", "nano": "nano", "htop": "htop", "btop": "btop", "top": "top", "lazygit": "lazygit",
         "git": "git", "cargo": "cargo", "npm": "npm", "pnpm": "pnpm", "yarn": "yarn", "node": "Node.js",
         "python3": "Python", "python": "Python", "make": "make", "yay": "yay", "pacman": "pacman", "man": "man",
         "less": "less", "ssh": "ssh", "tmux": "tmux", "zellij": "Zellij", "codex": "Codex", "aider": "Aider",
         "bash": "Shell", "zsh": "Shell", "fish": "Shell", "sh": "Shell", "nu": "Shell"}
HOST_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,40}$")


def _read(path: str, limit: int = 4096) -> str:
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
    except OSError:
        return ""
    try:
        return os.read(fd, limit).decode("utf-8", "replace")
    except OSError:
        return ""
    finally:
        os.close(fd)


def _children(pid: int) -> list[int]:
    out = []
    try:
        tasks = os.listdir(f"/proc/{pid}/task")[:64]
    except OSError:
        return out
    for t in tasks:
        for c in _read(f"/proc/{pid}/task/{t}/children").split()[:64]:
            if c.isdigit():
                out.append(int(c))
    return out


def _stat(pid: int) -> tuple[str, int] | None:
    raw = _read(f"/proc/{pid}/stat", 1024)
    close = raw.rfind(")")
    if close < 0:
        return None
    fields = raw[close + 2:].split()
    try:
        return raw[raw.find("(") + 1:close], int(fields[5])        # comm, tpgid
    except (IndexError, ValueError):
        return None


def _folder(pid: int) -> str:
    try:
        cwd = os.readlink(f"/proc/{pid}/cwd")
    except OSError:
        return ""
    home = os.path.expanduser("~")
    if cwd == home:
        return "~"
    name = os.path.basename(cwd.rstrip("/"))
    return name[:40] if name and name.isprintable() else ""


def _ssh_host(pid: int) -> str:
    args = _read(f"/proc/{pid}/cmdline", 4096).split("\0")
    hosts = [a for a in args[1:] if a and not a.startswith("-") and HOST_RE.match(a)]
    return hosts[0].split("@")[-1] if hosts else ""


def describe(terminal_pid: int) -> str:
    """"Claude Code in omarchy-dusk", "Shell in ~", "ssh to alien-win", or "" when it cannot be told."""
    shells = []
    for child in _children(terminal_pid):
        st = _stat(child)
        if st and st[1] > 0:
            shells.append((child, st[1]))
    if len(shells) != 1:
        return ""
    shell, fg = shells[0]
    target = fg if fg > 0 else shell
    st = _stat(target)
    if not st:
        return ""
    comm = st[0]
    name = NAMES.get(comm, comm[:24] if comm.isprintable() else "")
    if not name:
        return ""
    if comm == "ssh":
        host = _ssh_host(target)
        return f"ssh to {host}" if host else "ssh"
    folder = _folder(target)
    return f"{name} in {folder}" if folder else name
