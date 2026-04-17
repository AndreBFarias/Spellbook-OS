#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Modulo de compatibilidade cross-platform para scripts do Spellbook-OS.
Zero dependencias externas. Funciona em Linux, macOS e Windows.
"""

import sys
import os
from pathlib import Path


def safe_open(filepath, mode="r", **kwargs):
    """open() com encoding utf-8 por padrao (evita cp1252 no Windows)."""
    if "b" not in mode and "encoding" not in kwargs:
        kwargs["encoding"] = "utf-8"
    return open(filepath, mode, **kwargs)


def ensure_utf8_stdio():
    """Reconfigura stdout/stderr para UTF-8 (necessario no Windows)."""
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")


def supports_color():
    """Detecta suporte a cores ANSI no terminal."""
    if os.environ.get("NO_COLOR"):
        return False
    if os.environ.get("FORCE_COLOR"):
        return True
    if sys.platform == "win32":
        try:
            import ctypes
            kernel32 = ctypes.windll.kernel32
            handle = kernel32.GetStdHandle(-11)
            mode = ctypes.c_ulong()
            kernel32.GetConsoleMode(handle, ctypes.byref(mode))
            kernel32.SetConsoleMode(handle, mode.value | 0x0004)
            return True
        except Exception:
            return os.environ.get("TERM") is not None
    return hasattr(sys.stdout, "isatty") and sys.stdout.isatty()


class Colors:
    """Paleta Dracula com fallback para string vazia se sem suporte."""

    def __init__(self):
        enabled = supports_color()
        self.fg = "\033[38;2;248;248;242m" if enabled else ""
        self.bg = "\033[38;2;40;42;54m" if enabled else ""
        self.comment = "\033[38;2;98;114;164m" if enabled else ""
        self.cyan = "\033[38;2;139;233;253m" if enabled else ""
        self.green = "\033[38;2;80;250;123m" if enabled else ""
        self.orange = "\033[38;2;255;184;108m" if enabled else ""
        self.pink = "\033[38;2;255;121;198m" if enabled else ""
        self.purple = "\033[38;2;189;147;249m" if enabled else ""
        self.red = "\033[38;2;255;85;85m" if enabled else ""
        self.yellow = "\033[38;2;241;250;140m" if enabled else ""
        self.reset = "\033[0m" if enabled else ""
        self.bold = "\033[1m" if enabled else ""
        self.dim = "\033[2m" if enabled else ""


def detect_encoding(filepath):
    """Tenta detectar encoding de um arquivo: utf-8 -> latin-1 -> cp1252."""
    encodings = ["utf-8", "latin-1", "cp1252"]
    for enc in encodings:
        try:
            with open(filepath, "r", encoding=enc) as f:
                f.read(4096)
            return enc
        except (UnicodeDecodeError, UnicodeError):
            continue
    return "utf-8"


def normalize_path(filepath):
    """Resolve path para absoluto, normalizado para o SO."""
    return Path(filepath).resolve()


# "Não ha vento favoravel para quem não sabe aonde ir." -- Seneca
