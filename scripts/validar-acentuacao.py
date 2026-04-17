#!/usr/bin/env python3
"""
Valida acentuação PT-BR em strings de código, comentários e documentação.

Procura palavras comuns em PT-BR sem acento (ex.: "função", "não", "descrição")
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

# Palavra sem acento -> versão correta. Apenas casos inequívocos.
# Nomes técnicos (func_name, sao_paulo como slug) devem ser ignorados via
# # noqa-acento ou estarem dentro de strings que o regex não casa.
CORRECOES = {
    "não": "não",
    "função": "função",
    "funções": "funções",
    "execução": "execução",
    "execuções": "execuções",
    "descrição": "descrição",
    "descrições": "descrições",
    "configuração": "configuração",
    "configurações": "configurações",
    "operação": "operação",
    "operações": "operações",
    "informação": "informação",
    "informações": "informações",
    "validação": "validação",
    "validações": "validações",
    "instalação": "instalação",
    "instalações": "instalações",
    "remoção": "remoção",
    "remoções": "remoções",
    "seleção": "seleção",
    "seleções": "seleções",
    "ação": "ação",
    "ações": "ações",
    "sessão": "sessão",
    "sessões": "sessões",
    "atenção": "atenção",
    "atenções": "atenções",
    "direção": "direção",
    "direções": "direções",
    "verificação": "verificação",
    "verificações": "verificações",
    "criação": "criação",
    "criações": "criações",
    "opção": "opção",
    "opções": "opções",
    "diretório": "diretório",
    "diretórios": "diretórios",
    "crítico": "crítico",
    "críticos": "críticos",
    "crítica": "crítica",
    "críticas": "críticas",
    "último": "último",
    "últimos": "últimos",
    "última": "última",
    "últimas": "últimas",
    "próximo": "próximo",
    "próximos": "próximos",
    "próxima": "próxima",
    "próximas": "próximas",
    "período": "período",
    "períodos": "períodos",
    "histórico": "histórico",
    "históricos": "históricos",
    "único": "único",
    "únicos": "únicos",
    "única": "única",
    "únicas": "únicas",
    "caractere": "caractere",  # já correto, só para ignorar
    "caracteres": "caracteres",  # já correto, só para ignorar
}

# Remove entradas que são idênticas (adicionadas por engano)
CORRECOES = {k: v for k, v in CORRECOES.items() if k != v}

EXTENSIONS = (".py", ".zsh", ".sh", ".md")

# Contextos onde a palavra é detectada: apenas dentro de strings, comentários
# e docstrings — NUNCA em identificadores (function names, variáveis).
# Heurística: palavra precedida e seguida por espaço, aspas, hífen, acento
# ou início/fim de linha. Se vem após "def ", "function ", "alias ", ignora.
IDENT_PREFIX = re.compile(r"(?:def |function |alias |class )\s*$")


def check_file(path: Path, fix: bool = False) -> list[tuple[int, str, str, str]]:
    """Retorna lista de (linha_num, palavra_errada, palavra_correta, linha_texto)."""
    results = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines(keepends=False)
    except (UnicodeDecodeError, OSError):
        return []

    changed = False
    fixed_lines = []

    for i, line in enumerate(lines, start=1):
        if "# noqa-acento" in line:
            fixed_lines.append(line)
            continue

        new_line = line
        for errada, correta in CORRECOES.items():
            # Fronteira: início/fim de palavra, case-insensitive
            pattern = re.compile(rf"(?<![a-zA-Z0-9_]){re.escape(errada)}(?![a-zA-Z0-9_])", re.IGNORECASE)
            for m in pattern.finditer(line):
                # Skip se for identificador de função/variável (precedido por def/function)
                prefix = line[: m.start()]
                if IDENT_PREFIX.search(prefix):
                    continue
                # Skip se for dentro de identificador (ex.: minha_funcao)
                if prefix.rstrip().endswith(("_", ".", "-")):
                    continue
                results.append((i, m.group(), correta, line.strip()))
            if fix:
                # Preserva caso da primeira letra
                def repl(match):
                    original = match.group()
                    if original[0].isupper():
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
    # Skip venv, .oh-my-zsh, .git
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
            for lineno, errada, correta, texto in after:
                rel = f.relative_to(CONFIG_ROOT) if str(f).startswith(str(CONFIG_ROOT)) else f
                logging.warning("%s:%d: '%s' deveria ser '%s' (não corrigível)", rel, lineno, errada, correta)
                total_violations += 1
        else:
            for lineno, errada, correta, texto in before:
                rel = f.relative_to(CONFIG_ROOT) if str(f).startswith(str(CONFIG_ROOT)) else f
                logging.warning("%s:%d: '%s' deveria ser '%s'", rel, lineno, errada, correta)
                total_violations += 1

    if args.fix:
        logging.info("Total: %d corrigidas, %d pendentes", total_fixed, total_violations)
    else:
        if total_violations:
            logging.info("Total: %d violação(ões) em %d arquivo(s)", total_violations, len({f for f, *_ in []}))

    return 1 if total_violations > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
