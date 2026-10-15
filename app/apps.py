"""An app's name and category, from its desktop entry: the same files the app launcher reads.

A window's class is matched to an entry by its StartupWMClass, or by the entry's file name. The category comes from
the entry's Categories= line, mapped onto a handful of buckets like a phone's; a few apps that ship no entry of their
own (terminals started by hand, Steam games) are named here. Files are read with a size ceiling and a count ceiling,
and never through a symbolic link.
"""
from __future__ import annotations

import os

ENTRY_MAX = 64 * 1024
ENTRIES_MAX = 3000

# Desktop-entry categories, most telling first, and the bucket each belongs to.
MAP = [
    ("Game", "Games"),
    ("Development", "Development"), ("IDE", "Development"), ("TerminalEmulator", "Development"),
    ("WebBrowser", "Web"),
    ("InstantMessaging", "Social"), ("Chat", "Social"), ("IRCClient", "Social"), ("Email", "Social"),
    ("AudioVideo", "Entertainment"), ("Video", "Entertainment"), ("Audio", "Entertainment"), ("Player", "Entertainment"),
    ("Graphics", "Creativity"), ("2DGraphics", "Creativity"), ("3DGraphics", "Creativity"), ("Photography", "Creativity"),
    ("Office", "Productivity"), ("Education", "Productivity"), ("Science", "Productivity"),
    ("Network", "Web"),
    ("System", "Utilities"), ("Settings", "Utilities"), ("Utility", "Utilities"),
]

KNOWN = {
    "foot": ("Terminal", "Development"), "kitty": ("Terminal", "Development"), "alacritty": ("Terminal", "Development"),
    "com.mitchellh.ghostty": ("Ghostty", "Development"), "org.wezfurlong.wezterm": ("WezTerm", "Development"),
    "cs2": ("Counter-Strike 2", "Games"), "dota2": ("Dota 2", "Games"),
}


def entry_dirs() -> list[str]:
    home = os.path.expanduser("~")
    data = os.environ.get("XDG_DATA_HOME", "")
    if not data.startswith("/"):
        data = os.path.join(home, ".local", "share")
    return [os.path.join(data, "applications"), "/usr/share/applications",
            os.path.join(data, "flatpak", "exports", "share", "applications"),
            "/var/lib/flatpak/exports/share/applications"]


def _read(path: str) -> str:
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
    except OSError:
        return ""
    try:
        return os.read(fd, ENTRY_MAX).decode("utf-8", "replace")
    except OSError:
        return ""
    finally:
        os.close(fd)


def _fields(text: str) -> dict:
    out, inside = {}, False
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("["):
            inside = line == "[Desktop Entry]"
            continue
        if inside and "=" in line:
            k, v = line.split("=", 1)
            if k in ("Name", "Categories", "StartupWMClass", "NoDisplay") and k not in out:
                out[k] = v.strip()
    return out


def bucket(categories: str) -> str:
    have = set(c for c in categories.split(";") if c)
    for cat, name in MAP:
        if cat in have:
            return name
    return "Other"


class Resolver:
    """Looks entries up once per run, then answers from memory."""

    def __init__(self, dirs: list[str] | None = None) -> None:
        self.by_class: dict[str, tuple[str, str]] = {}
        self.by_file: dict[str, tuple[str, str]] = {}
        count = 0
        for d in dirs if dirs is not None else entry_dirs():
            try:
                names = sorted(os.listdir(d))
            except OSError:
                continue
            for name in names:
                if not name.endswith(".desktop") or count >= ENTRIES_MAX:
                    continue
                count += 1
                f = _fields(_read(os.path.join(d, name)))
                if not f.get("Name"):
                    continue
                info = (f["Name"][:64], bucket(f.get("Categories", "")))
                stem = name[: -len(".desktop")].lower()
                self.by_file.setdefault(stem, info)
                if f.get("StartupWMClass"):
                    self.by_class.setdefault(f["StartupWMClass"].lower(), info)

    def __call__(self, app: str) -> dict:
        key = app.lower()
        if key in KNOWN:
            name, cat = KNOWN[key]
        elif key.startswith("steam_app_"):
            name, cat = app, "Games"
        else:
            hit = self.by_class.get(key) or self.by_file.get(key)
            if not hit:
                # A reverse-DNS class (org.gnome.Nautilus) often matches an entry by its last part.
                tail = key.rsplit(".", 1)[-1]
                hit = next((v for k, v in self.by_file.items() if k == tail or k.endswith("." + tail)), None)
            name, cat = hit if hit else (app, "Other")
        return {"name": name, "category": cat}
