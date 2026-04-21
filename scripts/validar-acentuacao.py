#!/usr/bin/env python3
"""
Valida acentuação PT-BR em strings de código, comentários e documentação.

Procura palavras comuns em PT-BR sem acento (ex.: 'função', 'não', 'descrição')  # noqa-acento
em arquivos .py, .zsh, .sh, .md e reporta violações com arquivo:linha.

Uso:
    validar-acentuacao.py [--fix] [--paths ROOT [ROOT ...]]

Flags:
    --fix    Aplica correção automática em casos seguros (sem acentos ambíguos)
    --paths  Roots a escanear (default: functions/ scripts/ README.md)

Para silenciar falsos positivos, inclua "# noqa-acento" na mesma linha.
"""
import argparse
import logging
import re
import sys
from pathlib import Path

CONFIG_ROOT = Path(__file__).resolve().parent.parent

# Par "sem acento" -> "com acento". Montado via tuplas para evitar que o próprio
# script seja auto-corrompido quando rodado com --fix sobre si mesmo.
_PARES = [
    ("n" + "ao", "n" + "\u00e3o"),
    ("func" + "ao", "fun" + "\u00e7\u00e3o"),
    ("func" + "oes", "fun" + "\u00e7\u00f5es"),
    ("execuc" + "ao", "execu" + "\u00e7\u00e3o"),
    ("execuc" + "oes", "execu" + "\u00e7\u00f5es"),
    ("descric" + "ao", "descri" + "\u00e7\u00e3o"),
    ("descric" + "oes", "descri" + "\u00e7\u00f5es"),
    ("configurac" + "ao", "configura" + "\u00e7\u00e3o"),
    ("configurac" + "oes", "configura" + "\u00e7\u00f5es"),
    ("operac" + "ao", "opera" + "\u00e7\u00e3o"),
    ("operac" + "oes", "opera" + "\u00e7\u00f5es"),
    ("informac" + "ao", "informa" + "\u00e7\u00e3o"),
    ("informac" + "oes", "informa" + "\u00e7\u00f5es"),
    ("validac" + "ao", "valida" + "\u00e7\u00e3o"),
    ("validac" + "oes", "valida" + "\u00e7\u00f5es"),
    ("instalac" + "ao", "instala" + "\u00e7\u00e3o"),
    ("instalac" + "oes", "instala" + "\u00e7\u00f5es"),
    ("remoc" + "ao", "remo" + "\u00e7\u00e3o"),
    ("remoc" + "oes", "remo" + "\u00e7\u00f5es"),
    ("selec" + "ao", "sele" + "\u00e7\u00e3o"),
    ("selec" + "oes", "sele" + "\u00e7\u00f5es"),
    ("ac" + "ao", "a" + "\u00e7\u00e3o"),
    ("ac" + "oes", "a" + "\u00e7\u00f5es"),
    ("sess" + "ao", "sess" + "\u00e3o"),
    ("sess" + "oes", "sess" + "\u00f5es"),
    ("atenc" + "ao", "aten" + "\u00e7\u00e3o"),
    ("direc" + "ao", "dire" + "\u00e7\u00e3o"),
    ("verificac" + "ao", "verifica" + "\u00e7\u00e3o"),
    ("criac" + "ao", "cria" + "\u00e7\u00e3o"),
    ("opc" + "ao", "op" + "\u00e7\u00e3o"),
    ("opc" + "oes", "op" + "\u00e7\u00f5es"),
    ("diretor" + "io", "diret" + "\u00f3rio"),
    ("diretor" + "ios", "diret" + "\u00f3rios"),
    ("crit" + "ico", "cr" + "\u00edtico"),
    ("crit" + "ica", "cr" + "\u00edtica"),
    ("ult" + "imo", "" + "\u00faltimo"),
    ("ult" + "imos", "" + "\u00faltimos"),
    ("ult" + "ima", "" + "\u00faltima"),
    ("prox" + "imo", "pr" + "\u00f3ximo"),
    ("peri" + "odo", "per" + "\u00edodo"),
    ("hist" + "orico", "hist" + "\u00f3rico"),
    ("un" + "ico", "" + "\u00fanico"),
]
# noqa-acento — o bloco acima é construído via concatenação para que o próprio
# script não seja sobrescrito quando --fix rodar sobre si mesmo.

CORRECOES = {errada: correta for errada, correta in _PARES}

EXTENSIONS = (".py", ".zsh", ".sh", ".md")

# Contextos onde a palavra é detectada: strings, comentários, docstrings —
# NUNCA identificadores (function names, variáveis).
IDENT_PREFIX = re.compile(r"(?:def |function |alias |class |local )\s*$")


def check_file(path: Path, fix: bool = False) -> list[tuple[int, str, str, str]]:
    results = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines(keepends=False)
    except (UnicodeDecodeError, OSError):
        return []

    changed = False
    fixed_lines = []

    for i, line in enumerate(lines, start=1):
        if "# noqa-acento" in line or "noqa-acento" in line:
            fixed_lines.append(line)
            continue

        new_line = line
        for errada, correta in CORRECOES.items():
            pattern = re.compile(
                rf"(?<![a-zA-Z0-9_]){re.escape(errada)}(?![a-zA-Z0-9_])",
                re.IGNORECASE,
            )
            for m in pattern.finditer(line):
                prefix = line[: m.start()]
                # Skip se precedido por palavra-chave de declaração
                if IDENT_PREFIX.search(prefix):
                    continue
                # Skip se é parte de identificador (prefixo _ . - ou $)
                if prefix.rstrip().endswith(("_", ".", "-", "$", "{", "=")):
                    continue
                results.append((i, m.group(), correta, line.strip()))
            if fix:
                def repl(match):
                    orig = match.group()
                    prefix = line[: match.start()]
                    if IDENT_PREFIX.search(prefix):
                        return orig
                    if prefix.rstrip().endswith(("_", ".", "-", "$", "{", "=")):
                        return orig
                    if orig[0].isupper():
                        return correta[0].upper() + correta[1:]
                    return correta
                new_line = pattern.sub(repl, new_line)

        if fix and new_line != line:
            changed = True
        fixed_lines.append(new_line)

    if fix and changed:
        path.write_text("\n".join(fixed_lines) + ("\n" if lines else ""), encoding="utf-8")

    return results


def iter_target_files(paths: list[Path]) -> list[Path]:
    files = []
    for root in paths:
        root = root.resolve()
        if root.is_file():
            if root.suffix in EXTENSIONS:
                files.append(root)
        elif root.is_dir():
            for ext in EXTENSIONS:
                files.extend(root.rglob(f"*{ext}"))
    excluded = ("/.git/", "/venv/", "/.venv/", "/.oh-my-zsh/", "/node_modules/", "/__pycache__/")
    return [f for f in files if not any(e in str(f) for e in excluded)]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fix", action="store_true", help="Aplica correções automáticas")
    parser.add_argument("--paths", nargs="+", type=Path, help="Caminhos a escanear")
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(message)s",
    )

    if not args.paths:
        args.paths = [
            CONFIG_ROOT / "functions",
            CONFIG_ROOT / "scripts",
        ]
        readme = CONFIG_ROOT / "README.md"
        if readme.exists():
            args.paths.append(readme)

    files = iter_target_files(args.paths)
    total_violations = 0
    total_fixed = 0

    for f in files:
        before = check_file(f, fix=False)
        if not before:
            continue
        if args.fix:
            check_file(f, fix=True)
            after = check_file(f, fix=False)
            total_fixed += len(before) - len(after)
            for lineno, errada, correta, _ in after:
                rel = f.relative_to(CONFIG_ROOT) if str(f).startswith(str(CONFIG_ROOT)) else f
                logging.warning("%s:%d: %r → %r (pendente)", rel, lineno, errada, correta)
                total_violations += 1
        else:
            for lineno, errada, correta, _ in before:
                rel = f.relative_to(CONFIG_ROOT) if str(f).startswith(str(CONFIG_ROOT)) else f
                logging.warning("%s:%d: %r → %r", rel, lineno, errada, correta)
                total_violations += 1

    if args.fix:
        logging.info("Total: %d corrigidas, %d pendentes", total_fixed, total_violations)
    elif total_violations:
        logging.info("Total: %d violação(ões)", total_violations)

    return 1 if total_violations > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
