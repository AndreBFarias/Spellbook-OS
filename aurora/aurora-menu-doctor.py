#!/usr/bin/env python3
"""Aurora — doctor do menu de lançamento. Detecta e corrige drift dos .desktop.

PRINCÍPIO: não existe nome de aplicativo neste arquivo.

Tudo é derivado do estado real da máquina (o binário existe? o flatpak está
instalado? o desktop-id está vivo?). É o que separa "autoadaptável" de "lista
que alguém precisa vir editar": quando o dono remover o próximo app, a guarda
pega sozinha, sem ninguém tocar aqui.

O incidente que originou o script (2026-09-15): a leva-04 removeu 20 aplicativos
e os lançadores ficaram. gedit, mpv, guvcview, nautilus e ghostty seguiam no menu
apontando para binários que não existem mais, e o ~/.config/mimeapps.list tinha
21 associações para eles — inclusive text/plain, que o COSMIC oferecia como
opção de editor padrão.

MODOS
  --check   (padrão) read-only. Imprime o laudo. Sai 1 se houver problema.
  --fix     corrige o que é seguro corrigir. Sai 0 salvo erro real.
  --json    laudo em JSON (para o briefing de sessão / automação).

REGRA DE OURO (idempotência): rodar --fix duas vezes; a segunda tem de ser no-op.
Valide com:  aurora-menu-doctor.py --fix && aurora-menu-doctor.py --check

O QUE ELE NUNCA TOCA
  Arquivos fora de $XDG_DATA_HOME. /usr/share/applications é território do dpkg:
  mover um .desktop de lá deixa o pacote quebrado para o apt e o próximo upgrade
  o traz de volta. Lá o doctor só relata — a correção é remover o pacote.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

# ---------------------------------------------------------------------------
# Política de desempate. A ÚNICA regra de gosto do dono que vive aqui, e ela
# nomeia ambientes de desktop, não aplicativos: "na duplicidade o COSMIC vence"
# (decisão de 2026-09-15). Usada só para escolher o substituto quando um default
# de mimetype aponta para um app que morreu. Prefixos de desktop-id, em ordem.
PREFERENCIA = ("com.system76.Cosmic", "org.gnome.", "org.kde.")

# Programas que apenas embrulham o comando real. Ler o primeiro token do Exec e
# achar `systemd-run` conclui que o app está vivo quando ele foi removido — a
# armadilha que o README do Migração-OS documenta com o caso do firefox.
WRAPPERS = {"env", "nice", "systemd-run", "gtk-launch", "dbus-run-session",
            "setsid", "nohup", "ionice", "pkexec"}

# Wrappers que atravessam para OUTRO sistema de arquivos. O alvo depois deles não
# existe no host e nunca vai existir — julgá-lo condena o app vivo. Medido em
# 2026-09-15: os 7 lançadores do Citrix apontam para /opt/Citrix/ICAClient/... ,
# que só existe dentro do container Ubuntu do distrobox. Aqui quem responde pela
# saúde do lançador é o wrapper.
NAMESPACE = {"distrobox-enter", "toolbox", "flatpak-spawn", "podman", "docker",
             "lxc", "ssh", "chroot"}

# `bash -c "cd /opt/x && .venv/bin/python3 src/tray.py"` guarda o comando real
# dentro de uma string de shell, com cd, && e caminhos relativos. Resolver isso
# direito é escrever um parser de shell; resolver por cima acusa o inocente (foi
# o que aconteceu com o elden-ring-tracker, que está vivo). Não se julga.
SHELL = {"sh", "bash", "zsh", "fish", "dash"}

# app-id reverse-DNS: pelo menos dois pontos, como org.telegram.desktop.
RE_APPID = re.compile(r"^[A-Za-z][A-Za-z0-9_-]*(\.[A-Za-z0-9_-]+){2,}$")

# A quarentena fica FORA de qualquer diretório de applications, e isso não é
# detalhe de arrumação. O XDG varre os subdiretórios e transforma
# `applications/.bak/x.desktop` no desktop-id `.bak-x.desktop`: o app continua
# registrado como handler de mimetype depois de "removido". Medido em 2026-09-15
# — o mimeinfo.cache tinha `.aurora-orphan-bak-org.gimp.GIMP.desktop`, herdado do
# aurora-desktop-guards, que guarda os órfãos dentro do próprio applications/
# desde 2026-06-22.
# O mapa de StartupWMClass vive no MeowSystem, junto dos outros mapas de ícone.
WMCLASS_MAP = Path.home()/"Desenvolvimento/MeowSystem/assets/icones/wmclass.map"

QUARENTENA_REL = "aurora-menu-quarentena"
QUARENTENA_LEGADA_REL = "applications/.aurora-orphan-bak"


# ---------------------------------------------------------------------------
# Descoberta do ambiente XDG


def data_home() -> Path:
    return Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")


def quarentena() -> Path:
    return data_home() / QUARENTENA_REL


def quarentena_legada() -> Path:
    return data_home() / QUARENTENA_LEGADA_REL


def dirs_applications() -> list[Path]:
    """Diretórios de .desktop na ordem de precedência XDG (o primeiro vence)."""
    dirs = [data_home() / "applications"]
    bruto = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    for d in bruto.split(":"):
        if d:
            dirs.append(Path(d) / "applications")
    # Flatpak e snap exportam fora do XDG_DATA_DIRS em sessões não-gráficas
    # (o self-heal roda do .zshrc, onde o ambiente é mais pobre que o da sessão).
    for extra in (data_home() / "flatpak/exports/share/applications",
                  Path("/var/lib/flatpak/exports/share/applications"),
                  Path("/var/lib/snapd/desktop/applications")):
        if extra not in dirs:
            dirs.append(extra)
    return [d for d in dirs if d.is_dir()]


def desktop_id(arquivo: Path, raiz: Path) -> str:
    """O ID XDG: caminho relativo à raiz, com '/' virando '-'."""
    return str(arquivo.relative_to(raiz)).replace(os.sep, "-")


def em_quarentena(arq: Path) -> bool:
    return quarentena() in arq.parents or quarentena_legada() in arq.parents


def mapa_vivos() -> dict[str, Path]:
    """desktop-id -> arquivo que efetivamente vence a precedência XDG."""
    vivos: dict[str, Path] = {}
    for raiz in dirs_applications():
        for arq in raiz.rglob("*.desktop"):
            if em_quarentena(arq):
                continue  # senão o que foi removido volta a contar como vivo
            did = desktop_id(arq, raiz)
            vivos.setdefault(did, arq)  # primeiro a aparecer vence
    return vivos


# ---------------------------------------------------------------------------
# Leitura de .desktop


def campos(arq: Path) -> dict[str, str]:
    """Campos do grupo [Desktop Entry]. Só o primeiro grupo interessa aqui."""
    out: dict[str, str] = {}
    try:
        texto = arq.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return out
    dentro = False
    for linha in texto.splitlines():
        linha = linha.strip()
        if linha.startswith("["):
            if dentro:
                break
            dentro = linha == "[Desktop Entry]"
            continue
        if not dentro or "=" not in linha or linha.startswith("#"):
            continue
        chave, _, valor = linha.partition("=")
        out.setdefault(chave.strip(), valor.strip())
    return out


_FLATPAK_CACHE: set[str] | None = None
_FLATPAK_LIDO = False


def _flatpak_instalados() -> set[str] | None:
    """App-ids instalados (user + system), ou None quando não deu para saber.

    Uma listagem no lugar de um `flatpak info` por lançador: são 51 lançadores
    com `flatpak run` nesta máquina, e o self-heal roda a cada terminal novo.

    None e set() são coisas MUITO diferentes aqui. Se o flatpak não responde e
    isso virasse um conjunto vazio, TODO lançador flatpak seria declarado órfão
    de uma vez e o --fix varreria o menu inteiro para a quarentena. None significa
    "não sei", e quem não sabe não condena.
    """
    global _FLATPAK_CACHE, _FLATPAK_LIDO
    if _FLATPAK_LIDO:
        return _FLATPAK_CACHE
    _FLATPAK_LIDO = True
    try:
        r = subprocess.run(["flatpak", "list", "--columns=application"],
                           capture_output=True, text=True, timeout=30)
        if r.returncode == 0:
            ids = {l.strip() for l in r.stdout.splitlines() if l.strip()}
            # Listagem vazia é legítima (ninguém instalou nada), mas indistinguível
            # de uma falha silenciosa. Com zero flatpaks não há o que julgar mesmo.
            _FLATPAK_CACHE = ids or None
    except (OSError, subprocess.SubprocessError):
        _FLATPAK_CACHE = None  # sem flatpak no PATH: não rebaixa ninguém
    return _FLATPAK_CACHE


def _flatpak_instalado(appid: str) -> bool:
    instalados = _flatpak_instalados()
    return True if instalados is None else appid in instalados


def _existe(caminho: str) -> bool:
    return bool(caminho and (shutil.which(caminho) or Path(caminho).is_file()))


def _flatpak_ok(resto: list[str]) -> bool:
    """`flatpak run [flags] <app-id> [args]` — quem responde é o flatpak.

    O app-id se acha por forma (reverse-DNS), não por posição. Posição falha: o
    Exec do Telegram é `... --file-forwarding org.telegram.desktop -- @@u %u @@`,
    e cortar no `--` como se fosse o separador do systemd-run deixa `@@u` no lugar
    do app-id — foi assim que o Telegram, instalado, apareceu como órfão na
    primeira passagem de 2026-09-15.
    """
    for t in resto:
        t = t.strip("\"'")
        if RE_APPID.match(t):
            return _flatpak_instalado(t)
    return True


def _flatpak_id_do_exec(linha: str) -> str | None:
    """O app-id do Flatpak que este Exec lança, se for um."""
    toks = [x.strip("\"'") for x in (linha or "").split()]
    if not toks or Path(toks[0]).name != "flatpak":
        return None
    for x in toks[1:]:
        if RE_APPID.match(x):
            return x
    return None


_WAYLAND_CACHE: dict[str, bool] = {}


def _usa_wayland(appid: str) -> bool:
    """O Flatpak tem socket wayland? Então sob COSMIC o app_id é minúsculo.

    É o que separa um StartupWMClass suspeito de um legítimo: `Boxy SVG` não
    pode ser app_id de Wayland, mas `com.meowsystem.Painel` pode.
    """
    if appid in _WAYLAND_CACHE:
        return _WAYLAND_CACHE[appid]
    try:
        r = subprocess.run(["flatpak", "info", "--show-permissions", appid],
                           capture_output=True, text=True, timeout=15)
        _WAYLAND_CACHE[appid] = "wayland" in r.stdout
    except (OSError, subprocess.SubprocessError):
        _WAYLAND_CACHE[appid] = False
    return _WAYLAND_CACHE[appid]


def ler_wmclass_map() -> dict[str, str]:
    """desktop-id -> StartupWMClass correto, conferido a olho."""
    if not WMCLASS_MAP.is_file():
        return {}
    fora = {}
    for linha in WMCLASS_MAP.read_text(encoding="utf-8", errors="replace").splitlines():
        linha = linha.strip()
        if not linha or linha.startswith("#") or ":" not in linha:
            continue
        alvo, _, valor = linha.partition(":")
        alvo, valor = alvo.strip(), valor.strip()
        if alvo and valor:
            fora[alvo] = valor
    return fora


def alvo_existe(c: dict[str, str]) -> bool:
    """O programa que este .desktop chama ainda existe?

    Na dúvida devolve True. Um falso negativo esconde um app vivo do menu, o que
    é pior do que deixar um lançador morto aparecendo — e este script move
    arquivo, então o custo do erro não é simétrico.
    """
    tryexec = c.get("TryExec", "").strip().strip("\"'")
    if tryexec:
        # TryExec é a declaração explícita do empacotador. Quando existe, manda.
        if _existe(tryexec):
            return True
        # O distrobox escreve TryExec com argumentos, fora do spec. Sem esta
        # segunda chance, os 7 lançadores do Citrix caem como órfãos.
        partes = tryexec.split()
        return len(partes) > 1 and _existe(partes[0])

    linha = c.get("Exec", "")
    if not linha:
        return True  # sem Exec é outro problema, tratado no diagnóstico

    toks = [t for t in linha.split() if not t.startswith("%")]

    # Desembrulha em camadas: quem manda é sempre o PRIMEIRO comando da linha, e
    # é ele que decide como o resto deve ser lido. Processar o `--` antes de saber
    # quem está na frente é o que quebrava o Telegram.
    while toks:
        cabeca = Path(toks[0].strip("\"'")).name

        if cabeca == "flatpak":
            return _flatpak_ok(toks[1:])

        if cabeca in NAMESPACE:
            return _existe(toks[0].strip("\"'"))

        if cabeca in SHELL and any(t == "-c" for t in toks[1:3]):
            return True  # script inline: não julgável

        if cabeca in WRAPPERS:
            if "--" in toks:              # separador explícito: o resto é o alvo
                toks = toks[toks.index("--") + 1:]
                continue
            toks = toks[1:]               # senão, pula o wrapper e suas flags
            while toks and (toks[0].startswith("-") or "=" in toks[0]):
                toks = toks[1:]
            continue

        return _existe(toks[0].strip("\"'"))

    return True


# ---------------------------------------------------------------------------
# Diagnóstico


class Laudo:
    def __init__(self) -> None:
        self.problemas: list[dict] = []

    def add(self, tipo: str, alvo: str, detalhe: str, corrigivel: bool) -> None:
        self.problemas.append({"tipo": tipo, "alvo": alvo,
                               "detalhe": detalhe, "corrigivel": corrigivel})

    def por_tipo(self, tipo: str) -> list[dict]:
        return [p for p in self.problemas if p["tipo"] == tipo]


def diagnosticar() -> Laudo:
    laudo = Laudo()
    meu = data_home() / "applications"
    vivos = mapa_vivos()

    # Órfão legado ainda dentro de applications/: o XDG o indexa com o nome do
    # subdiretório na frente, então ele continua valendo como handler.
    if quarentena_legada().is_dir():
        for arq in sorted(quarentena_legada().glob("*.desktop")):
            laudo.add("quarentena_indexada", str(arq),
                      f"{arq.name} está sob applications/ e o XDG ainda o registra "
                      f"como '{QUARENTENA_LEGADA_REL.split('/')[-1]}-{arq.name}'", True)

    for raiz in dirs_applications():
        # Tudo sob ~/.local/share é do dono, exports de flatpak inclusive: quando
        # o app não está instalado, o flatpak não reescreve mais aquele arquivo, e
        # `flatpak repair` não o remove (verificado em 2026-09-15).
        for arq in sorted(raiz.rglob("*.desktop")):
            if em_quarentena(arq):
                continue
            meu_territorio = data_home() in arq.parents or arq.parent == meu
            c = campos(arq)

            if c.get("Type", "Application") != "Application":
                continue  # Link/Directory não têm Exec

            # Um .desktop sem Exec só incomoda se aparecer no menu. Escondido, ele
            # costuma existir de propósito: os lançadores do Citrix têm apenas
            # NoDisplay + StartupWMClass, para o compositor casar a janela com o
            # ícone. Acusá-los foi falso positivo na primeira passagem.
            escondido = c.get("NoDisplay") == "true" or c.get("Hidden") == "true"
            if not escondido and (not c.get("Name") or not c.get("Exec")):
                laudo.add("campo_faltando", str(arq),
                          "visível no menu e sem Name= ou Exec=", meu_territorio)
                continue
            if not c.get("Exec"):
                continue

            if not alvo_existe(c):
                laudo.add("orfao", str(arq),
                          f"{c.get('Name')} → alvo inexistente: "
                          f"{c.get('TryExec') or c.get('Exec', '')[:60]}",
                          meu_territorio)

            if meu_territorio:
                modo = arq.stat().st_mode & 0o777
                if not modo & 0o044:
                    laudo.add("permissao", str(arq),
                              f"modo {modo:o} — o launcher não consegue ler", True)

    # StartupWMClass: o que o dock usa para casar JANELA com .desktop.
    corrigir = ler_wmclass_map()
    # Só o .desktop que VENCE a precedência XDG: é ele que o dock lê. O mesmo
    # id em dois diretórios apareceria duas vezes, e um deles nem está em uso.
    for did, arq in sorted(vivos.items()):
            c = campos(arq)
            if c.get("Type", "Application") != "Application":
                continue
            atual = c.get("StartupWMClass")
            quer = corrigir.get(did)
            if quer and atual != quer:
                # Corrigível: o valor certo foi observado e está no mapa.
                laudo.add("wmclass_errado", str(arq),
                          f"{c.get('Name')}: declara {atual!r}, a janela usa {quer!r}",
                          data_home() in arq.parents or arq.parent == meu)
            elif atual and not quer:
                # Suspeito: Flatpak em Wayland não pode ter app_id com espaço
                # ou maiúscula. Só avisa — o valor certo se observa, não se deduz.
                appid = _flatpak_id_do_exec(c.get("Exec", ""))
                # O app-id reverse-DNS É um app_id de Wayland válido, maiúsculas
                # e tudo: `md.obsidian.Obsidian` está certo. O sinal de erro é o
                # valor ser OUTRA coisa com cara de WM_CLASS do X11.
                parece_x11 = (" " in atual or atual != atual.lower()) and atual != appid
                if appid and parece_x11 and _usa_wayland(appid):
                    laudo.add("wmclass_suspeito", str(arq),
                              f"{c.get('Name')}: {atual!r} tem espaço ou maiúscula, "
                              f"mas o app roda em Wayland (app_id é minúsculo). "
                              f"Abra o app e veja o nome no tooltip do dock.", False)

    # mimeapps.list: associações para desktop-ids que não existem mais.
    for lista in (Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "mimeapps.list",
                  meu / "mimeapps.list"):
        if not lista.is_file():
            continue
        for n, linha in enumerate(lista.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            if "=" not in linha or linha.startswith(("[", "#")):
                continue
            chave, _, valor = linha.partition("=")
            mortos = [i for i in valor.split(";") if i.strip() and i.strip() not in vivos]
            if mortos:
                laudo.add("mime_morto", f"{lista}:{n}",
                          f"{chave.strip()} → {', '.join(mortos)}", True)

    # Cache do menu mais velho que o .desktop mais novo: algo foi instalado ou
    # removido e o launcher segue mostrando o estado anterior até alguém rodar
    # update-desktop-database.
    #
    # Compara-se com os ARQUIVOS, não com o mtime do diretório. O
    # update-desktop-database grava o cache por temporário+rename, e o rename
    # atualiza o mtime do próprio diretório: comparar com ele deixa o diretório
    # eternamente "mais novo" que o cache que acabou de ser escrito, e o doctor
    # entraria em laço tentando consertar o que já estava certo.
    cache = meu / "mimeinfo.cache"
    if meu.is_dir():
        entradas = [a.stat().st_mtime for a in meu.glob("*.desktop")]
        if entradas and (not cache.exists() or cache.stat().st_mtime < max(entradas)):
            laudo.add("cache_velho", str(cache),
                      "mimeinfo.cache mais antigo que os lançadores", True)

    return laudo


# ---------------------------------------------------------------------------
# Correção


def substituto(mimetype: str, vivos: dict[str, Path]) -> str | None:
    """Um app VIVO que declare este mimetype, escolhido pela PREFERENCIA."""
    candidatos = []
    for did, arq in vivos.items():
        c = campos(arq)
        if c.get("NoDisplay") == "true" or c.get("Hidden") == "true":
            continue
        if mimetype in [m for m in c.get("MimeType", "").split(";") if m]:
            if alvo_existe(c):
                candidatos.append(did)
    if not candidatos:
        return None
    def rank(did: str) -> tuple[int, str]:
        for i, pref in enumerate(PREFERENCIA):
            if did.startswith(pref):
                return (i, did)
        return (len(PREFERENCIA), did)
    return sorted(candidatos, key=rank)[0]


def corrigir(laudo: Laudo) -> list[str]:
    acoes: list[str] = []
    meu = data_home() / "applications"
    quar = quarentena()
    vivos = mapa_vivos()

    # 1. Permissões antes de tudo: um .desktop ilegível não pode ser diagnosticado.
    for p in laudo.por_tipo("permissao"):
        if p["corrigivel"]:
            os.chmod(p["alvo"], 0o644)
            acoes.append(f"perm 644: {Path(p['alvo']).name}")

    # 2. Órfãos → quarentena. Mover, nunca apagar: se o diagnóstico errar, o dono
    #    devolve o arquivo. Um `rm` aqui seria irreversível por definição.
    orfaos = [p for p in laudo.por_tipo("orfao") + laudo.por_tipo("campo_faltando")
              + laudo.por_tipo("quarentena_indexada") if p["corrigivel"]]
    if orfaos:
        quar.mkdir(parents=True, exist_ok=True)
        for p in orfaos:
            origem = Path(p["alvo"])
            if not origem.exists():
                continue
            destino = quar / origem.name
            if destino.exists():
                destino = quar / f"{origem.stem}.{int(time.time())}{origem.suffix}"
            shutil.move(str(origem), str(destino))
            acoes.append(f"quarentena: {origem.name}")
        # A quarentena legada some quando esvazia; deixá-la faz o XDG varrer um
        # diretório a mais para sempre.
        legada = quarentena_legada()
        if legada.is_dir() and not any(legada.iterdir()):
            legada.rmdir()
            acoes.append(f"removido diretório vazio {legada.name}")
        vivos = mapa_vivos()  # o mapa mudou; releia antes de escolher substitutos

    # 3. StartupWMClass: escreve o valor observado, preservando o resto do arquivo.
    for p_ in laudo.por_tipo("wmclass_errado"):
        if not p_["corrigivel"]:
            continue
        arq = Path(p_["alvo"])
        did = next((desktop_id(arq, r) for r in dirs_applications() if r in arq.parents), arq.name)
        quer = ler_wmclass_map().get(did)
        if not quer:
            continue
        linhas, posto = [], False
        for linha in arq.read_text(encoding="utf-8", errors="replace").splitlines():
            if linha.startswith("StartupWMClass="):
                linhas.append("StartupWMClass=" + quer); posto = True
            else:
                linhas.append(linha)
        if not posto:
            # Sem a chave, entra logo depois do [Desktop Entry] — no fim do
            # arquivo ela cairia dentro de um [Desktop Action] e não valeria.
            saida = []
            for linha in linhas:
                saida.append(linha)
                if not posto and linha.strip() == "[Desktop Entry]":
                    saida.append("StartupWMClass=" + quer); posto = True
            linhas = saida
        if posto:
            arq.write_text("\n".join(linhas) + "\n", encoding="utf-8")
            acoes.append(f"StartupWMClass: {arq.name} -> {quer}")

    # 4. mimeapps.list: tira os ids mortos. Quando a linha é um DEFAULT e fica
    #    sem ninguém, promove um app vivo em vez de deixar o mimetype órfão —
    #    senão o dono perde a associação e descobre isso ao clicar num arquivo.
    for lista in {Path(p["alvo"].rsplit(":", 1)[0]) for p in laudo.por_tipo("mime_morto")}:
        texto = lista.read_text(encoding="utf-8", errors="replace")
        lista.with_suffix(lista.suffix + f".antes-do-doctor-{time.strftime('%Y%m%d-%H%M%S')}"
                          ).write_text(texto, encoding="utf-8")
        grupo, saida = "", []
        for linha in texto.splitlines():
            crua = linha.strip()
            if crua.startswith("["):
                grupo = crua
                saida.append(linha)
                continue
            if "=" not in crua or crua.startswith("#"):
                saida.append(linha)
                continue
            chave, _, valor = crua.partition("=")
            ids = [i.strip() for i in valor.split(";") if i.strip()]
            mantidos = [i for i in ids if i in vivos]
            if mantidos == ids:
                saida.append(linha)
                continue
            if not mantidos and grupo == "[Default Applications]":
                novo = substituto(chave.strip(), vivos)
                if novo:
                    saida.append(f"{chave.strip()}={novo}")
                    acoes.append(f"default {chave.strip()} → {novo}")
                    continue
            if mantidos:
                saida.append(f"{chave.strip()}={';'.join(mantidos)};")
                acoes.append(f"mimeapps: {chave.strip()} perdeu "
                             f"{len(ids) - len(mantidos)} id(s) morto(s)")
            else:
                acoes.append(f"mimeapps: linha removida ({chave.strip()})")
        lista.write_text("\n".join(saida) + "\n", encoding="utf-8")

    # 4. Cache. Por último, e só uma vez, depois de todo mundo ter escrito.
    if acoes or laudo.por_tipo("cache_velho"):
        subprocess.run(["update-desktop-database", str(meu)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        acoes.append("cache do menu atualizado")

    return acoes


# ---------------------------------------------------------------------------


ROTULOS = {
    "orfao": "lançadores apontando para programa que não existe mais",
    "quarentena_indexada": "órfãos guardados dentro de applications/ (o XDG ainda os lê)",
    "campo_faltando": "lançadores sem Name= ou Exec=",
    "permissao": "lançadores que o menu não consegue ler",
    "mime_morto": "associações de arquivo para app removido",
    "wmclass_errado": "janelas que o dock não casa com o app (StartupWMClass)",
    "wmclass_suspeito": "StartupWMClass que provavelmente não casa sob Wayland",
    "cache_velho": "cache do menu desatualizado",
}


def imprimir(laudo: Laudo) -> None:
    if not laudo.problemas:
        print("[menu-doctor] menu íntegro — nenhum problema encontrado.")
        return
    print(f"[menu-doctor] {len(laudo.problemas)} problema(s):\n")
    for tipo, rotulo in ROTULOS.items():
        achados = laudo.por_tipo(tipo)
        if not achados:
            continue
        print(f"  {rotulo} ({len(achados)}):")
        for p in achados:
            marca = " " if p["corrigivel"] else "!"
            print(f"   {marca} {p['alvo']}")
            print(f"       {p['detalhe']}")
        print()
    fora = [p for p in laudo.problemas
            if not p["corrigivel"] and p["tipo"] != "wmclass_suspeito"]
    if fora:
        print(f"  ! {len(fora)} fora de {data_home()} — território do dpkg/flatpak.\n"
              f"    O doctor não mexe: corrija removendo o pacote.")
    susp = laudo.por_tipo("wmclass_suspeito")
    if susp:
        print(f"  ! os {len(susp)} suspeitos acima não são corrigidos sozinhos: o valor\n"
              f"    certo se observa, não se deduz. Abra o app, leia o nome que o dock\n"
              f"    mostra no tooltip da janela, e escreva a linha em\n    {WMCLASS_MAP}")


def main() -> int:
    ap = argparse.ArgumentParser(description="Doctor do menu de lançamento (Aurora).")
    ap.add_argument("--check", action="store_true", help="só diagnostica (padrão)")
    ap.add_argument("--fix", action="store_true", help="corrige o que é seguro")
    ap.add_argument("--json", action="store_true", help="laudo em JSON")
    ap.add_argument("--quiet", action="store_true", help="só o código de saída")
    ap.add_argument("--melhor-para", metavar="MIMETYPE",
                    help="imprime o desktop-id vivo preferido para o mimetype "
                         "(quem decide é PREFERENCIA). Sai 1 se não houver nenhum.")
    ap.add_argument("--alvo-vivo", metavar="ARQUIVO",
                    help="sai 0 se o programa que esse .desktop chama existe, 1 se não. "
                         "Para quem instala .desktop e precisa decidir antes de copiar.")
    args = ap.parse_args()

    # Existe para o aplicar_overrides.sh do Dracula_OS-Theme, que copiava os 10
    # overrides sem perguntar e reinstalava 5 lançadores de apps desinstalados a
    # cada `apt` — desfazendo a limpeza do doctor num laço que ninguém via.
    if args.alvo_vivo:
        arq = Path(args.alvo_vivo)
        if not arq.is_file():
            return 1
        return 0 if alvo_existe(campos(arq)) else 1

    # Serve para que appliers não precisem repetir a política de desempate. Foi
    # repetindo-a que o aurora-editor-apply.sh ficou com "gedit" escrito no corpo
    # e seguiu tentando impor um editor que não existe mais.
    if args.melhor_para:
        escolhido = substituto(args.melhor_para, mapa_vivos())
        if not escolhido:
            return 1
        print(escolhido)
        return 0

    laudo = diagnosticar()

    if args.fix:
        # Converge numa invocação só. Corrigir um problema revela outro: mover um
        # lançador órfão para a quarentena MATA as associações de mimetype que
        # apontavam para ele, e essas não estavam no laudo — foram criadas pela
        # própria correção. Sem este laço, a segunda chamada do script ainda
        # imprimia ações e a regra de ouro reprovava (medido em 2026-09-15).
        acoes: list[str] = []
        for _ in range(4):
            novas = corrigir(laudo)
            if not novas:
                break
            acoes += novas
            laudo = diagnosticar()
        else:
            print("[menu-doctor] AVISO: não convergiu em 4 rodadas — "
                  "alguma correção está desfazendo outra.", file=sys.stderr)
        if args.json:
            print(json.dumps({"acoes": acoes, "antes": laudo.problemas},
                             ensure_ascii=False, indent=2))
        elif not args.quiet:
            if acoes:
                print(f"[menu-doctor] {len(acoes)} ação(ões):")
                for a in acoes:
                    print(f"  - {a}")
            else:
                print("[menu-doctor] nada a fazer — já consistente.")
        return 0

    if args.json:
        print(json.dumps(laudo.problemas, ensure_ascii=False, indent=2))
    elif not args.quiet:
        imprimir(laudo)
    # O RC RESPONDE "HA TRABALHO PARA O --fix?", NÃO "HA ALGO IMPERFEITO?"
    # (2026-09-18). Antes era `1 if laudo.problemas`, e isso criava um laco
    # não convergente com o aurora-self-heal.zsh:152-158, que roda
    # `--check --quiet` e enfileira o `--fix` quando o rc != 0: os dois
    # `wmclass_suspeito` (ONLYOFFICE, Telegram) sao, por desenho, os unicos
    # que o --fix NUNCA corrige — o próprio laudo diz "o valor certo se
    # observa, não se deduz". Resultado medido: "1 fix(es) aplicado(s)" a cada
    # terminal aberto, para sempre, sem nada mudar. E a mesma armadilha do
    # xbindkeys (leva-06 §4), com detector e applier ambos do Aurora.
    # Os nao-corrigiveis CONTINUAM impressos: a informação e para o humano,
    # so não serve mais de gatilho para um reparo que não existe.
    return 1 if any(p["corrigivel"] for p in laudo.problemas) else 0


if __name__ == "__main__":
    sys.exit(main())
