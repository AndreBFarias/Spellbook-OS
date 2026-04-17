#!/usr/bin/env python3
"""
Gera arquivos de completion zsh (_<funcao>) a partir de metadados em
comentários nos arquivos functions/*.zsh.

Convenção (ver completions/CONVENCAO.md):
    # Propósito: <descrição>
    # Uso: <nome> <arg1> [arg2] [--flag1] [--flag2]
    # Flags: --flag1=<descrição>
    #        --flag2=<descrição>
    # Completa:
    #   <arg1>=<completer>
    #   [arg2]=<completer>
    nome() { ... }

Uso:
    gerar-completions.py [--dry-run] [--verbose] [--func NOME]
"""
import argparse
import logging
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

CONFIG_ROOT = Path(__file__).resolve().parent.parent
FUNCTIONS_DIR = CONFIG_ROOT / "functions"
COMPLETIONS_DIR = CONFIG_ROOT / "completions"

RE_PURPOSE = re.compile(r"^\s*#\s*Prop[oó]sito:\s*(.*)$", re.IGNORECASE)
RE_USAGE = re.compile(r"^\s*#\s*Uso:\s*(.*)$", re.IGNORECASE)
RE_FLAGS_HEAD = re.compile(r"^\s*#\s*Flags:\s*(.*)$", re.IGNORECASE)
RE_COMPLETA_HEAD = re.compile(r"^\s*#\s*Completa:\s*(.*)$", re.IGNORECASE)
RE_CONT = re.compile(r"^\s*#\s+(\S.*)$")
RE_FUNC_DEF = re.compile(
    r"^\s*([a-zA-Z][a-zA-Z0-9_]*)\s*\(\)\s*\{"
    r"|^\s*function\s+([a-zA-Z][a-zA-Z0-9_]+)\s*\{"
)
RE_ARG_TOKEN = re.compile(r"<([^>]+)>|\[([^\]]+)\]")
RE_OVERRIDE = re.compile(r"^\s*#\s*OVERRIDE\b", re.IGNORECASE)


@dataclass
class FuncMeta:
    name: str
    source: Path
    purpose: str = ""
    usage: str = ""
    flags: dict = field(default_factory=dict)
    completa: dict = field(default_factory=dict)

    def has_metadata(self) -> bool:
        return bool(self.purpose or self.usage)


def parse_flag_line(line: str, into: dict) -> None:
    if "=" not in line:
        return
    flag, desc = line.split("=", 1)
    flag = flag.strip()
    desc = desc.strip()
    if flag.startswith("-"):
        into[flag] = desc


def parse_completa_line(line: str, into: dict) -> None:
    if "=" not in line:
        return
    arg, completer = line.split("=", 1)
    arg = arg.strip().strip("<>[]")
    completer = completer.strip()
    if arg and completer:
        into[arg] = completer


def parse_file(path: Path) -> list[FuncMeta]:
    result: list[FuncMeta] = []
    purpose = ""
    usage = ""
    flags: dict = {}
    completa: dict = {}
    mode = None

    with path.open("r", encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n")
            stripped = line.strip()

            if not stripped:
                purpose, usage, flags, completa, mode = "", "", {}, {}, None
                continue

            m = RE_PURPOSE.match(line)
            if m:
                purpose = m.group(1).strip()
                mode = None
                continue
            m = RE_USAGE.match(line)
            if m:
                usage = m.group(1).strip()
                mode = None
                continue
            m = RE_FLAGS_HEAD.match(line)
            if m:
                first = m.group(1).strip()
                if first:
                    parse_flag_line(first, flags)
                mode = "flags"
                continue
            m = RE_COMPLETA_HEAD.match(line)
            if m:
                first = m.group(1).strip()
                if first:
                    parse_completa_line(first, completa)
                mode = "completa"
                continue

            m = RE_CONT.match(line)
            if m and mode:
                if mode == "flags":
                    parse_flag_line(m.group(1), flags)
                elif mode == "completa":
                    parse_completa_line(m.group(1), completa)
                continue

            if stripped.startswith("#"):
                continue

            m = RE_FUNC_DEF.match(line)
            if m:
                name = next(filter(None, m.groups()), None)
                if name and not name.startswith("_"):
                    result.append(
                        FuncMeta(
                            name=name,
                            source=path,
                            purpose=purpose,
                            usage=usage,
                            flags=dict(flags),
                            completa=dict(completa),
                        )
                    )
                purpose, usage, flags, completa, mode = "", "", {}, {}, None
                continue

            purpose, usage, flags, completa, mode = "", "", {}, {}, None

    return result


def parse_usage_args(usage: str) -> list[tuple[str, bool]]:
    if not usage:
        return []
    args: list[tuple[str, bool]] = []
    for m in RE_ARG_TOKEN.finditer(usage):
        required = m.group(1) is not None
        name = (m.group(1) or m.group(2)).strip()
        if name.startswith("--") or name.startswith("-"):
            continue
        args.append((name, required))
    return args


def inferred_flags_from_usage(usage: str) -> list[str]:
    result = []
    for m in RE_ARG_TOKEN.finditer(usage):
        token = (m.group(1) or m.group(2) or "").strip()
        if token.startswith("--") or token.startswith("-"):
            for part in token.split():
                if part.startswith("-"):
                    result.append(part)
    return result


def escape_zsh(text: str) -> str:
    return text.replace("'", "'\\''").replace(":", "\\:")


def build_arguments(meta: FuncMeta) -> list[str]:
    lines: list[str] = []
    for flag, desc in meta.flags.items():
        lines.append(f"'{flag}[{escape_zsh(desc)}]'")
    for flag in inferred_flags_from_usage(meta.usage):
        if flag in meta.flags:
            continue
        lines.append(f"'{flag}[{flag}]'")

    args = parse_usage_args(meta.usage)
    pos = 1
    for name, required in args:
        completer = meta.completa.get(name, "")
        action = f"_{completer}" if completer else "_default"
        if completer.startswith("__"):
            action = completer
        label = escape_zsh(name)
        if required:
            lines.append(f"'{pos}:{label}:{action}'")
        else:
            lines.append(f"'::{label}:{action}'")
        pos += 1
    return lines


def render_completion(meta: FuncMeta) -> str:
    header = [
        f"#compdef {meta.name}",
        f"# Gerado automaticamente por scripts/gerar-completions.py",
        f"# Fonte: {meta.source.name}",
        f"# Propósito: {meta.purpose}" if meta.purpose else "",
        f"# Uso: {meta.usage}" if meta.usage else "",
    ]
    header = [h for h in header if h]

    args = build_arguments(meta)
    if not args:
        body = [
            f"_{meta.name}() {{",
            f"    _message 'sem argumentos definidos'",
            f"}}",
            f"_{meta.name} \"$@\"",
        ]
    else:
        body = [f"_{meta.name}() {{", "    _arguments \\"]
        for i, line in enumerate(args):
            sep = " \\" if i < len(args) - 1 else ""
            body.append(f"        {line}{sep}")
        body += [
            f"}}",
            f"_{meta.name} \"$@\"",
        ]

    return "\n".join(header + [""] + body) + "\n"


def is_override(path: Path) -> bool:
    if not path.exists():
        return False
    try:
        with path.open("r", encoding="utf-8") as f:
            return any(RE_OVERRIDE.match(line) for line in f.readlines()[:3])
    except OSError:
        return False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="Não escreve nada")
    parser.add_argument("--verbose", "-v", action="store_true")
    parser.add_argument("--func", help="Gera apenas para esta função")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s: %(message)s",
    )
    log = logging.getLogger("gerar-completions")

    if not FUNCTIONS_DIR.is_dir():
        log.error("Diretório de funções não encontrado: %s", FUNCTIONS_DIR)
        return 1
    COMPLETIONS_DIR.mkdir(exist_ok=True)

    all_metas: list[FuncMeta] = []
    for zsh_file in sorted(FUNCTIONS_DIR.glob("*.zsh")):
        if zsh_file.name.startswith("_"):
            continue
        metas = parse_file(zsh_file)
        all_metas.extend(metas)
        log.debug("%s: %d funções", zsh_file.name, len(metas))

    if args.func:
        all_metas = [m for m in all_metas if m.name == args.func]
        if not all_metas:
            log.error("Função não encontrada: %s", args.func)
            return 1

    geradas = 0
    ignoradas_override = 0
    ignoradas_sem_meta = 0

    for meta in all_metas:
        target = COMPLETIONS_DIR / f"_{meta.name}"
        if is_override(target):
            log.debug("OVERRIDE preservado: %s", target.name)
            ignoradas_override += 1
            continue
        if not meta.has_metadata():
            log.debug("Sem metadados, pulando: %s", meta.name)
            ignoradas_sem_meta += 1
            continue

        content = render_completion(meta)
        if args.dry_run:
            log.info("(dry-run) Geraria: %s", target)
            log.debug("\n%s", content)
        else:
            target.write_text(content, encoding="utf-8")
            log.debug("Gerado: %s", target.name)
        geradas += 1

    log.info(
        "Total: %d funções lidas | %d geradas | %d sem metadados | %d overrides preservados",
        len(all_metas),
        geradas,
        ignoradas_sem_meta,
        ignoradas_override,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
