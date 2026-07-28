#!/usr/bin/env python3
"""
Valida acentuação PT-BR em strings de código, comentários e documentação.

Procura palavras comuns em PT-BR sem acento (ex.: 'função', 'não', 'descrição')  # noqa-acento
em arquivos .py, .zsh, .sh, .md e reporta violações com arquivo:linha.

Uso:
    validar-acentuacao.py [--fix] [--paths ROOT [ROOT ...]] [--somente-diff-staged]

Flags:
    --fix    Aplica correção automática em casos seguros (sem acentos ambíguos)
    --paths  Roots a escanear (default: functions/ scripts/ README.md)
    --somente-diff-staged
             Restringe a atuação às linhas que o commit em curso tocou
             (intervalos de `git diff --cached -U0`). Sem a flag, o arquivo
             inteiro é considerado.

Para silenciar falsos positivos, inclua "# noqa-acento" na mesma linha.

FRONTEIRA PROSA vs IDENTIFICADOR (2026-07-28)
---------------------------------------------
Este script SÓ atua sobre prosa. A definição, em ordem de precedência:

  1. comentário                                    -> prosa
  2. docstring (string em posição de statement)    -> prosa
  3. string literal com 2+ palavras (tem espaço)   -> prosa
  4. string literal de palavra única               -> IDENTIFICADOR, intocável
  5. qualquer token fora de string e comentário    -> IDENTIFICADOR, intocável

O item 4 existe porque chave de dicionário, kwarg, path e classe CSS são
strings literais: `c["descricao"]` é uma string e NÃO é prosa. Reescrevê-la  # noqa-acento
produz KeyError em runtime. Prosa PT-BR tem mais de uma palavra; chave não tem.

Custo consciente da regra 4: label de palavra única (ex.: um texto de botão)
deixa de ser corrigida automaticamente. Ela continua sendo ACUSADA pelos gates
de repositório, então não sai do radar -- apenas deixa de ser reescrita sem
revisão. Correção silenciosa de identificador é dano; aviso de prosa é barato.
"""

import argparse
import io
import logging
import re
import subprocess
import sys
import tokenize
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

# Fim-de-linha virtual: uma região que vai até o fim da linha, qualquer que
# seja o comprimento dela.
_ATE_O_FIM = 10**9

# Literal de string em shell, com escape. Usado para achar prosa em .sh/.zsh,
# onde não existe tokenizador padrão.
_STRING_SHELL = re.compile(r'"([^"\\]*(?:\\.[^"\\]*)*)"|\'([^\'\\]*(?:\\.[^\'\\]*)*)\'')

# Code-span inline de Markdown.
_BACKTICK_MD = re.compile(r"`[^`]*`")

# Cabeçalho de hunk do diff unificado: @@ -a,b +c,d @@
_HUNK = re.compile(r"^@@ -\S+ \+(\d+)(?:,(\d+))? @@")


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


def _tem_espaco_interno(literal: str) -> bool:
    """Decide se um literal de string carrega prosa (2+ palavras) ou um nome.

    Prosa PT-BR tem espaço entre palavras; chave de dicionário, kwarg, path,
    nome de coluna e classe CSS não têm. É a fronteira da regra 4 do cabeçalho.
    """
    miolo = literal.strip()
    for aspas in ('"""', "'''", '"', "'"):
        if miolo.startswith(aspas) and miolo.endswith(aspas) and len(miolo) >= 2 * len(aspas):
            miolo = miolo[len(aspas) : -len(aspas)]
            break
    return " " in miolo.strip()


def _marcar(regioes: dict, inicio: tuple, fim: tuple) -> None:
    """Registra a região de um token (possivelmente multi-linha) como prosa."""
    linha_ini, col_ini = inicio
    linha_fim, col_fim = fim
    if linha_ini == linha_fim:
        regioes.setdefault(linha_ini, []).append((col_ini, col_fim))
        return
    regioes.setdefault(linha_ini, []).append((col_ini, _ATE_O_FIM))
    for numero in range(linha_ini + 1, linha_fim):
        regioes.setdefault(numero, []).append((0, _ATE_O_FIM))
    regioes.setdefault(linha_fim, []).append((0, col_fim))


def _regioes_prosa_py(texto: str):
    """Regiões de prosa num arquivo Python, via tokenize.

    Retorna None quando o arquivo não é tokenizável (sintaxe quebrada): o
    chamador trata isso como "não sei onde é prosa, logo não reescrevo nada".
    """
    regioes: dict[int, list[tuple[int, int]]] = {}
    try:
        tokens = list(tokenize.generate_tokens(io.StringIO(texto).readline))
    except (tokenize.TokenError, SyntaxError, IndentationError, ValueError):
        return None

    anterior = None
    for token in tokens:
        if token.type == tokenize.COMMENT:
            _marcar(regioes, token.start, token.end)
        elif token.type == tokenize.STRING:
            # Docstring: string que abre um statement. As demais só contam
            # como prosa se tiverem espaço interno (regra 3 vs regra 4).
            e_docstring = anterior in (
                None,
                tokenize.NEWLINE,
                tokenize.NL,
                tokenize.INDENT,
                tokenize.DEDENT,
            )
            if e_docstring or _tem_espaco_interno(token.string):
                _marcar(regioes, token.start, token.end)
        if token.type not in (tokenize.NL, tokenize.COMMENT):
            anterior = token.type
    return regioes


def _pos_comentario_shell(linha: str):
    """Coluna onde começa o comentário de uma linha de shell, ou None.

    Ignora `#` dentro de aspas, o shebang e as formas `$#` / `${#var}`.
    """
    aspas = None
    anterior = ""
    for pos, char in enumerate(linha):
        if aspas:
            if char == aspas and anterior != "\\":
                aspas = None
        elif char in ('"', "'"):
            aspas = char
        elif char == "#":
            if pos == 0 and linha.startswith("#!"):
                return None
            if anterior in ("$", "{"):
                continue
            return pos
        anterior = char
    return None


def _regioes_prosa_shell(linhas: list[str]) -> dict:
    """Regiões de prosa em .sh/.zsh: comentário e string com espaço interno."""
    regioes: dict[int, list[tuple[int, int]]] = {}
    for numero, linha in enumerate(linhas, start=1):
        pos = _pos_comentario_shell(linha)
        if pos is not None:
            regioes.setdefault(numero, []).append((pos, _ATE_O_FIM))
        for match in _STRING_SHELL.finditer(linha):
            if _tem_espaco_interno(match.group()):
                regioes.setdefault(numero, []).append((match.start(), match.end()))
    return regioes


def _regioes_prosa_md(linhas: list[str]) -> dict:
    """Regiões de prosa em Markdown: tudo, menos code-fence e code-span."""
    regioes: dict[int, list[tuple[int, int]]] = {}
    dentro_de_bloco = False
    for numero, linha in enumerate(linhas, start=1):
        if linha.lstrip().startswith("```"):
            dentro_de_bloco = not dentro_de_bloco
            continue
        if dentro_de_bloco:
            continue
        livres = []
        limite = 0
        for match in _BACKTICK_MD.finditer(linha):
            if match.start() > limite:
                livres.append((limite, match.start()))
            limite = match.end()
        livres.append((limite, _ATE_O_FIM))
        regioes[numero] = livres
    return regioes


def regioes_prosa(path: Path, texto: str, linhas: list[str]):
    """Mapa linha -> regiões onde reescrever é permitido. None = não sei."""
    sufixo = path.suffix
    if sufixo == ".py":
        return _regioes_prosa_py(texto)
    if sufixo in (".sh", ".zsh"):
        return _regioes_prosa_shell(linhas)
    if sufixo == ".md":
        return _regioes_prosa_md(linhas)
    return None


def _dentro(regioes_da_linha: list, inicio: int, fim: int) -> bool:
    return any(ini <= inicio and fim <= f for ini, f in regioes_da_linha)


def _dentro_de_code_span(line: str, inicio: int, fim: int) -> bool:
    """A posição está dentro de um par de crases na linha?"""
    for match in _BACKTICK_MD.finditer(line):
        if match.start() <= inicio and fim <= match.end():
            return True
    return False


def _permitido(line: str, regioes_da_linha: list, inicio: int, fim: int) -> bool:
    """Filtros de contexto, do mais estrutural ao mais local.

    A primeira barreira é posicional (a palavra está numa região de prosa?);
    as demais são as heurísticas de vizinhança que já existiam, mantidas como
    defesa em profundidade -- elas só REMOVEM correções, nunca acrescentam.
    """
    if not _dentro(regioes_da_linha, inicio, fim):
        return False
    prefix = line[:inicio]
    suffix = line[fim:]
    if IDENT_PREFIX.search(prefix):
        return False
    # Parte de identificador (prefixo _ . - $ { = ou ` de code-span).
    if prefix.rstrip().endswith(("_", ".", "-", "$", "{", "=", "`")):
        return False
    # Code-span inline DENTRO de prosa: numa docstring, `metodo(descricao)` é  # noqa-acento
    # referência a código, não texto PT-BR. O prefixo terminar em crase só pega
    # o primeiro token do span; aqui o span inteiro fica protegido.
    if _dentro_de_code_span(line, inicio, fim):
        return False
    # Parte de path, mesmo dentro de prosa: um comentário que cite
    # `data/historico` fala do diretório real, não de uma palavra PT-BR.  # noqa-acento
    if prefix.endswith(("/", "\\")) or suffix[:1] in ("/", "\\"):
        return False
    # Slug kebab-case (ex.: validacao-visual): nome, não texto PT-BR.
    if suffix[:1] == "-" and suffix[1:2].islower():
        return False
    return True


def _com_caixa(original: str, correta: str) -> str:
    """Aplica a correção preservando a caixa da ocorrência encontrada."""
    if original.isupper():
        return correta.upper()
    if original[0].isupper():
        return correta[0].upper() + correta[1:]
    return correta


def intervalos_staged(path: Path):
    """Intervalos de linha (1-based, inclusivos) que o commit em curso tocou.

    Retorna None quando o git não pôde responder -- nesse caso o chamador não
    restringe nada, porque a defesa de contexto (prosa vs identificador) já
    cobre a maior parte do risco e desligar a correção em silêncio seria pior.
    """
    # Pathspec e cwd ABSOLUTOS. Com pathspec relativo à raiz do repositório e
    # cwd num subdiretório, o git resolve o caminho a partir do cwd e devolve
    # vazio -- o que aqui significaria "nenhuma linha tocada" e desligaria a
    # correção em silêncio.
    caminho = path.resolve()
    try:
        resultado = subprocess.run(
            ["git", "diff", "--cached", "-U0", "--", str(caminho)],
            capture_output=True,
            text=True,
            timeout=15,
            cwd=str(caminho.parent),
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if resultado.returncode != 0:
        return None

    intervalos = []
    for linha in resultado.stdout.splitlines():
        match = _HUNK.match(linha)
        if not match:
            continue
        inicio = int(match.group(1))
        quantidade = int(match.group(2)) if match.group(2) is not None else 1
        if quantidade > 0:  # quantidade 0 é remoção pura: não há linha nova
            intervalos.append((inicio, inicio + quantidade - 1))
    return intervalos


def check_file(
    path: Path, fix: bool = False, intervalos: list | None = None
) -> list[tuple[int, str, str, str]]:
    results = []
    try:
        texto = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return []
    lines = texto.splitlines(keepends=False)

    regioes = regioes_prosa(path, texto, lines)
    if regioes is None:
        # Arquivo cujo contexto não sabemos ler (sintaxe quebrada, extensão
        # inesperada). Reescrever às cegas é o defeito que esta versão fecha.
        logging.debug("%s: contexto não analisável, nada será reescrito", path)
        regioes = {}

    changed = False
    fixed_lines = []

    for i, line in enumerate(lines, start=1):
        if has_noqa_marker(line):
            fixed_lines.append(line)
            continue

        if intervalos is not None and not any(
            ini <= i <= fim for ini, fim in intervalos
        ):
            # Fora das linhas que o commit tocou (--somente-diff-staged).
            fixed_lines.append(line)
            continue

        regioes_da_linha = regioes.get(i, [])
        if not regioes_da_linha:
            fixed_lines.append(line)
            continue

        # Todas as posições são calculadas sobre a linha ORIGINAL e aplicadas
        # depois, da direita para a esquerda. Substituir durante a varredura
        # desloca os offsets (a forma acentuada tem comprimento diferente) e
        # faz o filtro de contexto inspecionar o trecho errado.
        substituicoes = []
        for errada, correta in CORRECOES.items():
            pattern = re.compile(
                rf"(?<![a-zA-Z0-9_]){re.escape(errada)}(?![a-zA-Z0-9_])",
                re.IGNORECASE,
            )
            for m in pattern.finditer(line):
                if not _permitido(line, regioes_da_linha, m.start(), m.end()):
                    continue
                results.append((i, m.group(), correta, line.strip()))
                substituicoes.append((m.start(), m.end(), _com_caixa(m.group(), correta)))

        new_line = line
        if fix and substituicoes:
            for inicio, fim, texto_novo in sorted(substituicoes, reverse=True):
                new_line = new_line[:inicio] + texto_novo + new_line[fim:]

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
    parser.add_argument(
        "--somente-diff-staged",
        action="store_true",
        help="Atua apenas nas linhas tocadas pelo commit em curso",
    )
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
        intervalos = intervalos_staged(f) if args.somente_diff_staged else None
        before = check_file(f, fix=False, intervalos=intervalos)
        if not before:
            continue
        rel = (
            str(f.relative_to(CONFIG_ROOT))
            if str(f).startswith(str(CONFIG_ROOT))
            else str(f)
        )
        if args.fix:
            check_file(f, fix=True, intervalos=intervalos)
            after = check_file(f, fix=False, intervalos=intervalos)
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
