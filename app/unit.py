"""The Plasma edition's recorder as a systemd user service, set up only when you press "Start recording".

The unit runs this very helper (`serve`) by absolute path with an isolated Python, and is written with the same
no-follow, owner-checked, atomic write as everything else, into your own systemd user directory.
"""
from __future__ import annotations

import os
import pathlib
import secrets
import stat
import subprocess

UNIT = "app.duduphudu.hourglass.service"
SYSTEMCTL = "/usr/bin/systemctl"


def unit_dir() -> pathlib.Path:
    base = os.environ.get("XDG_CONFIG_HOME", "")
    if not base.startswith("/"):
        base = os.path.join(os.path.expanduser("~"), ".config")
    return pathlib.Path(base) / "systemd" / "user"


def unit_text() -> str:
    helper = pathlib.Path(__file__).resolve().parent.parent / "bin" / "hourglass"
    if any(ch in str(helper) for ch in "\n\"'\\%$ "):
        raise ValueError("the plugin's path cannot be written into a unit safely")
    return "\n".join([
        "[Unit]",
        "Description=Hourglass screen time recorder",
        "PartOf=graphical-session.target",
        "After=graphical-session.target",
        # Removing the widget removes the helper: then the unit is skipped, not restarted every ten seconds.
        f"ConditionPathExists={helper}",
        "",
        "[Service]",
        f"ExecStart=/usr/bin/python3 -I {helper} serve",
        "Restart=on-failure",
        "RestartSec=10",
        "",
        "[Install]",
        "WantedBy=graphical-session.target",
        "",
    ])


def _write(path: pathlib.Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    d = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
    tmp = f".{path.name}.{secrets.token_hex(8)}.tmp"
    try:
        try:
            info = os.stat(path.name, dir_fd=d, follow_symlinks=False)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
                raise OSError(f"{path}: not a regular file of ours")
        except FileNotFoundError:
            pass
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o644, dir_fd=d)
        try:
            os.write(fd, text.encode())
            os.fsync(fd)
        finally:
            os.close(fd)
        os.rename(tmp, path.name, src_dir_fd=d, dst_dir_fd=d)
        tmp = ""
    finally:
        if tmp:
            try:
                os.unlink(tmp, dir_fd=d)
            except OSError:
                pass
        os.close(d)


def _systemctl(*args: str) -> int:
    env = {"PATH": "/usr/bin", "HOME": os.path.expanduser("~"),
           "XDG_RUNTIME_DIR": os.environ.get("XDG_RUNTIME_DIR", "")}
    try:
        return subprocess.run([SYSTEMCTL, "--user", *args], env=env, timeout=20,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode
    except (OSError, subprocess.SubprocessError):
        return 1


def install() -> int:
    _write(unit_dir() / UNIT, unit_text())
    if _systemctl("daemon-reload") != 0:
        return 1
    return _systemctl("enable", "--now", UNIT)


def remove() -> int:
    _systemctl("disable", "--now", UNIT)
    try:
        (unit_dir() / UNIT).unlink()
    except FileNotFoundError:
        pass
    return _systemctl("daemon-reload")
