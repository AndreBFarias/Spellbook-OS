#!/usr/bin/env python3
"""Aviso + correcao tardia de nome de fornecedor de IA colado dentro de um
identificador snake_case (ex: um_dois_tres). \\b de regex não separa por
underscore, entao esses casos escapam do scanner amplo do pre-commit.

Primeira vez que um identificador assim aparece staged: so avisa, não mexe.
Se o MESMO identificador (por nome, em qualquer arquivo) aparecer staged de
novo numa proxima tentativa de commit: substitui o pedaco por "agente" e
re-stage, igual ao resto do pre-commit.

DUAS GUARDAS (2026-07-30, sprint INFRA-HOOK-COMMIT-MSG-MODELO-IA)
-----------------------------------------------------------------
Ate 2026-07-29 este era o unico mutador do fluxo de commit sem nenhuma
mitigacao: lia o ARQUIVO INTEIRO e reescrevia identificador em linha que
ninguem tinha editado. Foi assim que um path de diretorio real virou outro,
dentro de uma string, em `scripts/dossie_tipo.py` (commit 15712a12 do
protocolo-ouroboros, restaurado em bfac3d78). O identificador da constante
ficou intacto e so o VALOR mudou -- nome certo apontando para lugar
inexistente, o dano mais dificil de enxergar num diff.

(1) So as linhas que o commit em curso TOCOU. Mesma restricao que os blocos
    [3/6] e [7] do pre-commit global ganharam em 2026-07-28, pelo mesmo
    motivo.

(2) So identificador que o commit esta INTRODUZINDO. Se o nome ja existe no
    HEAD do repositorio, ele e vocabulario estabelecido -- nome de diretorio
    real, chave de schema, constante de modulo -- e não um vazamento novo;
    reescrever isso e corrupcao, não anonimato. Esta e a excecao estreita
    pedida pelo dono ("um except bem especifico pra não travar as financas do
    projeto sem quebrar a ideia original do hook"): no protocolo-ouroboros ha
    126 identificadores distintos nessa situacao, 1.161 ocorrencias, e 24
    deles ja estavam armados no estado de escalonamento.

    A excecao NÃO cobre atribuicao de autoria: "gerado por <modelo>" e prosa,
    não identificador snake_case, e nunca chega a este script -- quem trata
    disso e o bloco [3/6] do pre-commit (conteudo) e o commit-msg (mensagem).

    A guarda tambem não desarma a escalada original: enquanto o commit não
    entra, o identificador novo continua fora do HEAD, entao o segundo
    aviso ainda substitui, exatamente como a docstring de 2026-07-23 prometia.

Em duvida, NÃO reescreve. Sem git, sem HEAD ou sem intervalo de diff o script
vira no-op: deixar passar custa um aviso, reescrever por engano custa uma
sessao de arqueologia.
"""
import json
import os
import re
import subprocess
import sys

STATE_FILE = os.path.expanduser("~/.local/share/spellbook/ai_identifier_warnings.json")

VENDOR_WORDS = {
    "claude", "anthropic", "openai", "chatgpt", "gemini", "deepseek",
    "aider", "windsurf", "codeium", "tabnine", "opus", "sonnet", "haiku", "fable",
}

IDENTIFIER_RE = re.compile(r"\b[A-Za-z][A-Za-z0-9]*(?:_[A-Za-z0-9]+)+\b")

# Cabecalho de hunk do `git diff -U0`: "@@ -a,b +c,d @@". Interessa so o lado
# "+", que numera as linhas do arquivo como ele esta agora.
HUNK_RE = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")

_head_cache: dict[str, bool] = {}


def load_warned():
    try:
        with open(STATE_FILE) as f:
            return set(json.load(f))
    except Exception:
        return set()


def save_warned(warned):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(sorted(warned), f)


def linhas_tocadas(filepath):
    """Linhas (1-based) que o commit em curso adicionou ou alterou.

    Conjunto vazio quer dizer "não sei" -- e quem chama não mexe em nada.
    """
    try:
        r = subprocess.run(
            ["git", "diff", "--cached", "-U0", "--", filepath],
            capture_output=True, text=True, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return set()
    if r.returncode != 0:
        return set()

    tocadas = set()
    for linha in r.stdout.splitlines():
        m = HUNK_RE.match(linha)
        if not m:
            continue
        inicio = int(m.group(1))
        quantas = 1 if m.group(2) is None else int(m.group(2))
        if quantas > 0:
            tocadas.update(range(inicio, inicio + quantas))
    return tocadas


def ja_existe_no_head(ident):
    """True se o identificador ja e vocabulario do repositorio.

    Fail-safe deliberado: qualquer falha do git responde True. Fora de um
    repositorio, ou antes do primeiro commit, o script prefere não reescrever.
    """
    chave = ident.lower()
    if chave in _head_cache:
        return _head_cache[chave]
    try:
        r = subprocess.run(
            ["git", "grep", "-i", "-I", "-F", "-q", "-e", ident, "HEAD"],
            capture_output=True, text=True, check=False,
        )
        # 0 = achou; 1 = não achou; qualquer outro = erro (sem HEAD, fora de repo).
        resposta = r.returncode != 1
    except (OSError, subprocess.SubprocessError):
        resposta = True
    _head_cache[chave] = resposta
    return resposta


def process_file(filepath, warned, new_warnings):
    tocadas = linhas_tocadas(filepath)
    if not tocadas:
        return False

    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            linhas = f.readlines()
    except Exception:
        return False

    changed = False

    def repl(m):
        nonlocal changed
        ident = m.group(0)
        parts = ident.split("_")
        if not any(p.lower() in VENDOR_WORDS for p in parts):
            return ident
        if ja_existe_no_head(ident):
            return ident
        if ident.lower() not in warned:
            new_warnings.append((filepath, ident))
            return ident
        changed = True
        fixed_parts = ["agente" if p.lower() in VENDOR_WORDS else p for p in parts]
        # colapsa "agente" repetido em sequencia (ex: um_dois_tres ->
        # agente_agente_agente -> agente)
        collapsed = []
        for p in fixed_parts:
            if p == "agente" and collapsed and collapsed[-1] == "agente":
                continue
            collapsed.append(p)
        return "_".join(collapsed)

    novas = [
        IDENTIFIER_RE.sub(repl, linha) if numero in tocadas else linha
        for numero, linha in enumerate(linhas, start=1)
    ]

    if changed:
        with open(filepath, "w", encoding="utf-8") as f:
            f.writelines(novas)

    return changed


def main() -> int:
    files = sys.argv[1:]
    warned = load_warned()
    new_warnings = []
    fixed_files = []

    for f in files:
        if process_file(f, warned, new_warnings):
            fixed_files.append(f)

    if new_warnings:
        for filepath, ident in new_warnings:
            print(
                f"  [aviso] identificador '{ident}' em {filepath} menciona "
                f"ferramenta de IA -- troque por um sinonimo. Se commitar de "
                f"novo sem trocar, vira termo generico automaticamente."
            )
        warned.update(ident.lower() for _, ident in new_warnings)
        save_warned(warned)

    if fixed_files:
        print(
            f"  [auto-fix] identificador(es) com mencao de IA (ja avisado "
            f"antes) substituidos: {', '.join(fixed_files)}"
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
