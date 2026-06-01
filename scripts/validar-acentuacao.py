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
    # Estende o dicionario fechando o gap do VALIDATOR_BRIEF (canonicos, exclusao,  # noqa-acento
    # proprio) e palavras comuns vistas no projeto:  # noqa-acento
    ("canon" + "ico", "can" + "\u00f4nico"),
    ("canon" + "icos", "can" + "\u00f4nicos"),
    ("exclus" + "ao", "exclus" + "\u00e3o"),
    ("exclus" + "oes", "exclus" + "\u00f5es"),
    ("propr" + "io", "pr" + "\u00f3prio"),
    ("propr" + "ia", "pr" + "\u00f3pria"),
    ("propr" + "ios", "pr" + "\u00f3prios"),
    ("propr" + "ias", "pr" + "\u00f3prias"),
    ("padr" + "ao", "padr" + "\u00e3o"),
    ("padr" + "oes", "padr" + "\u00f5es"),
    ("sec" + "ao", "se" + "\u00e7\u00e3o"),
    ("sec" + "oes", "se" + "\u00e7\u00f5es"),
    ("bot" + "ao", "bot" + "\u00e3o"),
    ("bot" + "oes", "bot" + "\u00f5es"),
    ("p" + "anico", "p" + "\u00e2nico"),
    ("usuar" + "io", "usu" + "\u00e1rio"),
    ("usuar" + "ios", "usu" + "\u00e1rios"),
    ("detecc" + "ao", "dete" + "\u00e7\u00e3o"),
    ("recuperac" + "ao", "recupera" + "\u00e7\u00e3o"),
    ("automat" + "ico", "autom" + "\u00e1tico"),
    ("automat" + "ica", "autom" + "\u00e1tica"),
    ("pag" + "ina", "p" + "\u00e1gina"),
    ("pag" + "inas", "p" + "\u00e1ginas"),
    ("inval" + "ido", "inv" + "\u00e1lido"),
    ("inval" + "ida", "inv" + "\u00e1lida"),
]
# noqa-acento — o bloco acima é construído via concatenação para que o próprio
# script não seja sobrescrito quando --fix rodar sobre si mesmo.

CORRECOES = {errada: correta for errada, correta in _PARES}

EXTENSIONS = (".py", ".zsh", ".sh", ".md")

# Contextos onde a palavra é detectada: strings, comentários, docstrings —
# NUNCA identificadores (function names, variáveis).
IDENT_PREFIX = re.compile(r"(?:def |function |alias |class |local )\s*$")

# Marker preciso de noqa (igual ao hook local do Nyx-Code desde sprint 201):
# <!-- noqa-acento -->, # noqa-acento, // noqa-acento.  # noqa-acento
_NOQA_PRECISE_RE = re.compile(r"(<!--|#|//)\s*noqa-acento(\s|-->|$)")


def has_noqa_marker(line: str) -> bool:
    """Backward-compat: aceita marker preciso (regex) OU substring antiga.

    Marker preciso: <!-- noqa-acento -->, # noqa-acento, // noqa-acento.
    Substring antiga: qualquer ocorrencia de 'noqa-acento' ou '# noqa-acento'  # noqa-acento
    na linha (forma legada anterior a sprint 201 do Nyx-Code).
    """
    if _NOQA_PRECISE_RE.search(line):
        return True
    if "# noqa-acento" in line or "noqa-acento" in line:  # noqa-acento
        return True
    return False


def check_file(path: Path, fix: bool = False) -> list[tuple[int, str, str, str]]:
    results = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines(keepends=False)
    except (UnicodeDecodeError, OSError):
        return []

    changed = False
    fixed_lines = []

    for i, line in enumerate(lines, start=1):
        if has_noqa_marker(line):
            fixed_lines.append(line)
            continue

        new_line = line
        for errada, correta in CORRECOES.items():
            pattern = re.compile(
                rf"(?<![a-zA-Z0-9_]){re.escape(errada)}(?![a-zA-Z0-9_])",
                re.IGNORECASE,
            )
            for m in pattern.finditer(line):
                if has_noqa_marker(line):
                    continue  # marker presente — silencia esta linha (defesa em profundidade)
                prefix = line[: m.start()]
                suffix = line[m.end() :]
                # Skip se precedido por palavra-chave de declaração
                if IDENT_PREFIX.search(prefix):
                    continue
                # Skip se é parte de identificador (prefixo _ . - $ { = ou ` de code-span)
                if prefix.rstrip().endswith(("_", ".", "-", "$", "{", "=", "`")):
                    continue
                # Skip se é slug kebab-case (ex.: validacao-visual) -- nome, não texto PT-BR
                if suffix[:1] == "-" and suffix[1:2].islower():
                    continue
                results.append((i, m.group(), correta, line.strip()))
            if fix:

                def repl(match):
                    orig = match.group()
                    prefix = line[: match.start()]
                    suffix = line[match.end() :]
                    if IDENT_PREFIX.search(prefix):
                        return orig
                    if prefix.rstrip().endswith(("_", ".", "-", "$", "{", "=", "`")):
                        return orig
                    if suffix[:1] == "-" and suffix[1:2].islower():
                        return orig
                    # Preservar capitalização do exemplo  # noqa-acento
                    if orig.isupper():
                        return correta.upper()
                    if orig[0].isupper():
                        return correta[0].upper() + correta[1:]
                    return correta

                new_line = pattern.sub(repl, new_line)

        if fix and new_line != line:
            changed = True
        fixed_lines.append(new_line)

    if fix and changed:
        path.write_text(
            "\n".join(fixed_lines) + ("\n" if lines else ""), encoding="utf-8"
        )

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
    excluded = (
        "/.git/",
        "/venv/",
        "/.venv/",
        "/.oh-my-zsh/",
        "/node_modules/",
        "/__pycache__/",
        "/docs/archive/",
    )
    return [f for f in files if not any(e in str(f) for e in excluded)]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--fix", action="store_true", help="Aplica correções automáticas"
    )
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
    fixed_files: dict[str, int] = {}  # arquivo -> palavras corrigidas
    pending_files: dict[str, int] = {}  # arquivo -> violações residuais

    for f in files:
        before = check_file(f, fix=False)
        if not before:
            continue
        rel = (
            str(f.relative_to(CONFIG_ROOT))
            if str(f).startswith(str(CONFIG_ROOT))
            else str(f)
        )
        if args.fix:
            check_file(f, fix=True)
            after = check_file(f, fix=False)
            n_fixed = len(before) - len(after)
            if n_fixed > 0:
                fixed_files[rel] = n_fixed
                total_fixed += n_fixed
            for lineno, errada, correta, _ in after:
                logging.warning(
                    "%s:%d: %r → %r (revisão manual)", rel, lineno, errada, correta
                )
                pending_files[rel] = pending_files.get(rel, 0) + 1
                total_violations += 1
        else:
            for lineno, errada, correta, _ in before:
                logging.warning("%s:%d: %r → %r", rel, lineno, errada, correta)
                pending_files[rel] = pending_files.get(rel, 0) + 1
                total_violations += 1

    # Politica: aplica a correção e informa -- duas listas separadas.
    if args.fix:
        if fixed_files:
            logging.info(
                "Corrigidos automaticamente: %d arquivo(s), %d palavra(s):",
                len(fixed_files),
                total_fixed,
            )
            for arq, n in sorted(fixed_files.items()):
                logging.info("  %s (%d)", arq, n)
        if pending_files:
            logging.warning(
                "Precisam de revisão manual: %d arquivo(s), %d palavra(s):",
                len(pending_files),
                total_violations,
            )
            for arq, n in sorted(pending_files.items()):
                logging.warning("  %s (%d)", arq, n)
        if not fixed_files and not pending_files:
            logging.info("Acentuação: nada a corrigir.")
    elif total_violations:
        logging.info(
            "Total: %d violação(ões) em %d arquivo(s)",
            total_violations,
            len(pending_files),
        )

    return 1 if total_violations > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
