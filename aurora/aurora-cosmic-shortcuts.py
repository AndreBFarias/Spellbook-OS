#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""aurora-cosmic-shortcuts.py — merge SEMANTICO dos atalhos custom do COSMIC.

Portado do Andromeda-OS (scripts/aurora-cosmic-shortcuts.py, 26.748 bytes) em
2026-09-11. NAO e o arquivo dela inteiro, e isso e deliberado — ver "O QUE NÃO
VEIO" abaixo. O que veio e o mecanismo, que e a parte que custou caro:

  IDEMPOTENCIA NÃO PODE DEPENDER DE METADADO QUE O DONO DO FORMATO PODE APAGAR.
  A versao anterior dela usava um comentario RON na primeira linha
  ("// managed-by-aurora") como marcador de "ja rodei". O próprio COSMIC
  reserializa esse arquivo e a serializacao DESCARTA COMENTARIOS. Em 2026-06-03
  o marcador evaporou e o self-heal ficou CEGO POR 562 EXECUÇÕES; quando os
  wrappers antigos foram apagados, os atalhos viraram Spawn de arquivo
  inexistente — a tecla parecia funcionar e não fazia nada, e nada no log
  denunciava.

  O substituto e comparar SEMANTICA: a identidade de um binding e
  (frozenset(modificadores), tecla em minusculas) -> ação normalizada, e so se
  escreve quando o SIGNIFICADO diverge. Reformatacao feita pelo COSMIC não vira
  churn, e edicao do dono fora da lista MANAGED e preservada.

  O opt-out e um ARQUIVO sentinela, não um comentario:
  ~/.config/cosmic/.aurora-shortcuts-off — justamente porque o COSMIC não tem
  como apaga-lo sem querer.

  A escrita e atomica e explora o inotify do daemon: os.replace dentro do MESMO
  diretório, para o cosmic-settings-daemon ver o IN_MOVED_TO e recarregar.

RETIRADO EM 2026-09-14, DEPOIS DE DERRUBAR A SESSÃO TRES VEZES:

  Ctrl+Alt+0 -> aurora-gpu-revive-trigger   FORA DA LISTA MANAGED.

  A justificativa para inclui-lo estava certa no diagnostico e errada na
  conclusao. Certa: o xbindkeys faz XGrabKey no X, sob cosmic-comp a tecla nunca
  chega, e o compositor e de fato o único que pode pegar essa combinacao agora.
  Errada: dai se concluiu que declara-la no compositor RESTAURAVA o botão de
  pânico. Nao restaurava — CRIAVA um atalho novo, com efeito que ninguem tinha
  medido sob Wayland. Enquanto so o xbindkeys o declarava, ele estava inerte, e
  a inercia escondia o problema.

  O que o aurora-gpu-revive faz, medido no journal de 14/09:

      20:00:43  1o aperto: recuperação forcada (gpu_recover + restart do compositor)
      20:00:43  kernel: amdgpu 0000:75:00.0: MODE2 reset
      20:00:46  gpu_recover OK -- device recuperado (DMUB reinit)
      20:00:46  gnome-shell não encontrado -- nada a reiniciar
      20:00:47  <sessão graficia reiniciou; todas as janelas fecharam>

  Sob X11 esse MODE2 reset era NÃO-DESTRUTIVO: quem segura as janelas e o X
  server, que sobrevive ao reset, e o `gnome-shell --replace` reconstroi a casca.
  Sob Wayland o cosmic-comp E o servidor e desenha pela mesma GPU que se esta
  resetando: as superficies morrem com ele. O próprio script anuncia a lacuna na
  linha que diz "gnome-shell não encontrado -- nada a reiniciar" — ele executa a
  parte destrutiva e não tem a parte que recuperava.

  Disparou tres vezes (19:58:38, 20:00:43, 20:02:52) e derrubou a sessão do dono
  nas tres. Enquanto o aurora-gpu-revive não tiver um caminho Wayland, um atalho
  que reinicia a sessão não pode morar numa combinacao em que se encosta sem
  querer. Para reiniciar a CASCA sem perder janela existe o Alt+F2
  (aurora-reiniciar-casca.sh), que e o que resolve o caso do dia a dia.

O QUE MUDOU EM 2026-09-14 (leva-03) — TRES DECISOES DE 11/09 FORAM REFUTADAS
POR MEDICAO, e a quarta foi confirmada. Registro do que se mediu:

  Shift+Super+S -> aurora-gradia-clipboard.sh   ENTROU. Em 11/09 ficou de fora
    com a justificativa de que o `Ctrl+Shift+S -> flatpak run ... --screenshot=FULL`
    do dono era um caminho "próprio e VIVO". Ele NÃO estava vivo: em 14/09 as
    18:06 o processo desse atalho foi encontrado PENDURADO em bwrap (PIDs
    142896/142897/142912/142913, tty1), e o log do próprio Gradia mostra por que:

        CRITICAL  Failed to read image from stdin.
        ValueError: No image data received from stdin.

    O main() do Gradia chama read_from_stdin() ANTES do app.run(); sob o Spawn do
    cosmic-comp o filho herda um pipe que nunca fecha, e o read() bloqueia para
    sempre — a janela nunca aparece. O atalho "existia" e não fazia nada, que e
    exatamente o modo de falha que este arquivo foi escrito para impedir. O
    aurora-gradia-clipboard.sh cura isso com `setsid ... </dev/null &`: o stdin
    fecha na hora, o Gradia loga o CRITICAL como ruido e segue para o argumento
    posicional. Medido funcionando as 18:09 (PID 145068, janela na tela).

  Alt+F2 -> aurora-reiniciar-painel.sh   ENTROU. Em 11/09 ficou de fora porque o
    script não existia nesta maquina. Foi portado em 14/09 (scp de
    /usr/local/bin da meowsystem, 16.886 bytes, v3.66) e agora existe. A regra
    "atalho morto e pior que atalho ausente" continua valendo e continua sendo
    conferida em tempo de execução pelo bloco de validação do main().

  Print -> System(Screenshot)   ENTROU, mas como TRAVA, não como correcao. A
    analise de 11/09 estava certa: o default do sistema (linha 114 de
    /usr/share/cosmic/.../v1/defaults) ja e System(Screenshot), e ele FUNCIONA —
    conferido em 14/09 por 12 capturas em ~/Imagens/Screenshots/, a mais recente
    as 17:45. Declarar explicitamente no custom não muda o comportamento de
    hoje; garante que um reset de defaults num próximo dist-upgrade não leve o
    Print junto. Custo zero, sobrevivencia garantida.

  Ctrl+Shift+V -> claude-paste-image.sh   CONTINUA FORA, e a analise de 11/09
    esta confirmada: atalho global consome a tecla antes do terminal e roubaria
    o colar nativo do cosmic-term (que usa bracketed paste; o wtype digita tecla
    a tecla e um texto multilinha seria EXECUTADO). O paste universal entrou em
    Super+V, a tecla livre que o próprio cabecalho do claude-paste-image.sh
    recomenda.

  E o Ctrl+V que o dono pediu? Não precisa de atalho nenhum. O agente Code
    2.1.270 ja le imagem do clipboard sozinho — ha `wl-paste --type image/png`
    dentro do binario. O que faltava era o PACOTE: wl-clipboard não estava
    instalado (so xclip/xsel, que sob cosmic-term nativo Wayland não enxergam o
    clipboard). Instalado em 14/09 junto com wtype. O Super+V fica como rede de
    seguranca para colar imagem em QUALQUER campo, não so no agente Code.

ORDEM OBRIGATORIA: so remova ~/.config/autostart/xbindkeys.desktop DEPOIS de
este script ter rodado e o Ctrl+Alt+0 ter sido testado. Nunca tirar o botão de
pânico antes de o substituto responder.

Uso:
    aurora-cosmic-shortcuts.py --check   # relata, não escreve (faca isto antes)
    aurora-cosmic-shortcuts.py           # aplica
"""

import os
import re
import sys

HOME = os.path.expanduser("~")
COSMIC = os.path.join(HOME, ".config", "cosmic")
SHORTCUTS_DIR = os.path.join(COSMIC, "com.system76.CosmicSettings.Shortcuts", "v1")
SHORTCUTS = os.path.join(SHORTCUTS_DIR, "custom")
SENTINELA = os.path.join(COSMIC, ".aurora-shortcuts-off")

REPO_AURORA = os.path.join(HOME, ".config", "zsh", "aurora")
GPU_TRIGGER = os.path.join(REPO_AURORA, "aurora-gpu-revive-trigger")

MANAGED = [
    {
        "mods": ["Ctrl", "Alt"],
        "key": "t",
        "action": 'Spawn("cosmic-term")',
        "desc": "Abrir terminal (Aurora)",
    },
    # --- leva-03 (2026-09-14) — ver cabecalho "O QUE MUDOU EM 2026-09-14" ---
    {
        "mods": [],
        "key": "Print",
        "action": "System(Screenshot)",
        "desc": "Print — tela de captura nativa do COSMIC (leva-03)",
    },
    {
        "mods": ["Super", "Shift"],
        "key": "s",
        "action": 'Spawn("/usr/local/bin/aurora-gradia-clipboard.sh")',
        "desc": "Print novo + edicao no Gradia (leva-03)",
    },
    {
        "mods": ["Super"],
        "key": "s",
        "action": "Disable",
        "desc": "Desativa ToggleStacking padrão pra liberar Super+Shift+S (leva-03)",
    },
    {
        "mods": ["Alt"],
        "key": "F2",
        "action": 'Spawn("/usr/local/bin/aurora-reiniciar-casca.sh")',
        "desc": "Reiniciar a casca do COSMIC — painel, dock, bg, OSD, launcher (leva-03)",
    },
    {
        "mods": ["Super"],
        "key": "v",
        "action": 'Spawn("/usr/local/bin/claude-paste-image.sh")',
        "desc": "Paste universal — texto ou imagem->path (leva-03, fallback do Ctrl+V)",
    },
    # --- 2026-09-18 — avancar e voltar o papel de parede ---------------------
    #
    # O DONO PROCUROU ISTO NO MENU DO BOTÃO DIREITO DA AREA DE TRABALHO. Nao
    # esta la, e nunca esteve: quem desenha aquele menu e o cosmic-files, o
    # binario e BYTE A BYTE IDENTICO ao da outra maquina da casa (sha256
    # 42813e2dc4443da1c6b329f9b3640bcd23f5062889dec3acae08f0be45b6fb8d, pacote
    # 1.8.0~1788375747~24.04~089ad2b nas duas), e a unica string de fundo que
    # ele tem e `change-wallpaper` ("Alterar o plano de fundo..."). Nao houve
    # regressao nem perda: o item não existe no COSMIC.
    #
    # O comando existe desde sempre, so não tinha tecla: `meow wallpaper
    # próximo|anterior` (wallpaper.sh:2704-2705). Ele fixa a imagem por 30 min
    # e o carrossel volta sozinho depois — ou na hora, com `meow wallpaper
    # carrossel`.
    #
    # POR QUE Ctrl+Alt+seta, e não a combinacao obvia: as setas com Super estao
    # TODAS tomadas pelos defaults do COSMIC — Super (Focus), Super+Shift
    # (Move), Super+Ctrl (workspace), Super+Alt (SwitchOutput) e
    # Super+Shift+Alt (MoveToOutput). Conferido em
    # /usr/share/cosmic/.../v1/defaults: `Ctrl+Alt`+seta não aparece uma vez.
    #
    # O alvo e ~/.local/bin/meow (o CLI que o MeowSystem instala) e não um
    # script deste repo, entao ele NÃO esta em ORPHAN_PREFIXES: se o MeowSystem
    # sair da maquina, a trava de X_OK aborta o apply e avisa, em vez de este
    # script apagar um atalho que o dono pos.
    {
        "mods": ["Ctrl", "Alt"],
        "key": "Right",
        "action": 'Spawn("/home/andrefarias/.local/bin/meow wallpaper próximo")',
        "desc": "Próximo papel de parede (fixa por 30m)",
    },
    {
        "mods": ["Ctrl", "Alt"],
        "key": "Left",
        "action": 'Spawn("/home/andrefarias/.local/bin/meow wallpaper anterior")',
        "desc": "Papel de parede anterior (fixa por 30m)",
    },
]

# Prefixos cujos Spawn orfaos podem ser removidos com seguranca: e onde ESTE
# repo instala os próprios alvos. Nao mexemos em Spawn de binario do sistema
# (cosmic-term) nem de app de terceiro (o `flatpak run ...` do dono).
ORPHAN_PREFIXES = (REPO_AURORA + os.sep, "/usr/local/bin/")


def strip_comments(txt):
    """Remove // e /* */ fora de string. O COSMIC apaga comentarios ao
    reserializar, mas o arquivo pode ter sido editado a mao com eles."""
    out, i, n = [], 0, len(txt)
    while i < n:
        c = txt[i]
        if c == '"':
            j = i + 1
            while j < n:
                if txt[j] == "\\":
                    j += 2
                    continue
                if txt[j] == '"':
                    break
                j += 1
            out.append(txt[i:j + 1])
            i = j + 1
        elif txt.startswith("//", i):
            j = txt.find("\n", i)
            i = n if j < 0 else j
        elif txt.startswith("/*", i):
            j = txt.find("*/", i)
            i = n if j < 0 else j + 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def corpo(txt):
    """Conteudo entre as chaves externas do mapa RON."""
    a = txt.find("{")
    b = txt.rfind("}")
    if a < 0 or b <= a:
        return ""
    return txt[a + 1:b]


def parse_entries(body):
    """[(texto_do_binding, texto_da_acao)] — split por virgula de topo."""
    entradas, buf, prof, i, n = [], [], 0, 0, len(body)
    while i < n:
        c = body[i]
        if c == '"':
            j = i + 1
            while j < n:
                if body[j] == "\\":
                    j += 2
                    continue
                if body[j] == '"':
                    break
                j += 1
            buf.append(body[i:j + 1])
            i = j + 1
            continue
        if c in "([{":
            prof += 1
        elif c in ")]}":
            prof -= 1
        if c == "," and prof == 0:
            entradas.append("".join(buf))
            buf = []
            i += 1
            continue
        buf.append(c)
        i += 1
    if "".join(buf).strip():
        entradas.append("".join(buf))

    pares = []
    for ent in entradas:
        if not ent.strip():
            continue
        # o ':' separador e o primeiro em profundidade 0
        prof, corte = 0, -1
        k = 0
        while k < len(ent):
            ch = ent[k]
            if ch == '"':
                m = k + 1
                while m < len(ent):
                    if ent[m] == "\\":
                        m += 2
                        continue
                    if ent[m] == '"':
                        break
                    m += 1
                k = m + 1
                continue
            if ch in "([{":
                prof += 1
            elif ch in ")]}":
                prof -= 1
            elif ch == ":" and prof == 0:
                corte = k
                break
            k += 1
        if corte < 0:
            continue
        pares.append((ent[:corte].strip(), ent[corte + 1:].strip()))
    return pares


_RE_MODS = re.compile(r"modifiers\s*:\s*\[([^\]]*)\]", re.S)
_RE_KEY = re.compile(r'key\s*:\s*"([^"]*)"')


def identidade(binding_txt):
    m = _RE_MODS.search(binding_txt)
    mods = frozenset(x.strip() for x in (m.group(1).split(",") if m else []) if x.strip())
    k = _RE_KEY.search(binding_txt)
    return (mods, (k.group(1) if k else "").lower())


def normaliza_acao(acao):
    return re.sub(r"\s+", " ", acao).strip().rstrip(",").strip()


def alvo_spawn(acao):
    m = re.match(r'^\s*Spawn\s*\(\s*"([^"]*)"\s*\)\s*$', normaliza_acao(acao))
    if not m:
        return None
    return m.group(1).split()[0] if m.group(1).strip() else None


def fmt_ident(ident):
    mods, key = ident
    return "+".join(sorted(mods) + [key]) if mods else key


def emite(mods, key, desc, acao):
    linhas = ["    ("]
    if not mods:
        # Lista vazia em UMA linha: e a forma que o COSMIC emite e que o
        # Andromeda-OS usa em producao no binding de Print. A variante
        # multilinha vazia ("[\n        ],") nunca foi testada contra o
        # parser RON do cosmic-settings-daemon — não se aposta o arquivo
        # inteiro de atalhos numa diferenca de formatacao.
        linhas.append("        modifiers: [],")
    else:
        linhas.append("        modifiers: [")
        for m in mods:
            linhas.append("            %s," % m)
        linhas.append("        ],")
    linhas.append('        key: "%s",' % key)
    if desc:
        linhas.append('        description: Some("%s"),' % desc)
    linhas.append("    ): %s," % acao)
    return "\n".join(linhas)


def main():
    check = "--check" in sys.argv[1:]

    if os.path.exists(SENTINELA):
        print("  --  opt-out ativo (%s) — nada a fazer" % SENTINELA)
        return 0

    de = os.environ.get("XDG_CURRENT_DESKTOP", "")
    if "COSMIC" not in de:
        print("  !!  desktop não e COSMIC (%s) — pulando" % (de or "desconhecido"))
        return 0

    for spec in MANAGED:
        alvo = alvo_spawn(spec["action"])
        if alvo and alvo.startswith("/") and not os.access(alvo, os.X_OK):
            print("  !!  ABORTA: alvo de %s não existe ou não e executavel: %s"
                  % (fmt_ident((frozenset(spec["mods"]), spec["key"].lower())), alvo))
            print("      atalho morto e pior que atalho ausente — nada foi escrito")
            return 1

    atual_txt = ""
    if os.path.exists(SHORTCUTS):
        with open(SHORTCUTS, encoding="utf-8") as fh:
            atual_txt = fh.read()

    entradas = parse_entries(corpo(strip_comments(atual_txt)))
    gerenciados = {(frozenset(s["mods"]), s["key"].lower()): s for s in MANAGED}

    sem_atual = {}
    for b, a in entradas:
        sem_atual[identidade(b)] = normaliza_acao(a)

    mantidos, vistos, mudancas = [], set(), []
    for b, a in entradas:
        ident = identidade(b)
        if ident in gerenciados:
            continue  # reemitido do canônico mais abaixo
        if ident in vistos:
            mudancas.append("binding duplicado removido: %s" % fmt_ident(ident))
            continue
        alvo = alvo_spawn(a)
        if alvo and alvo.startswith(ORPHAN_PREFIXES) and not os.path.exists(alvo):
            mudancas.append("Spawn orfao removido: %s -> %s (arquivo não existe)"
                            % (fmt_ident(ident), alvo))
            continue
        vistos.add(ident)
        mantidos.append((b.strip(), normaliza_acao(a), ident))

    sem_desejada = {i: a for (_, a, i) in mantidos}
    for spec in MANAGED:
        ident = (frozenset(spec["mods"]), spec["key"].lower())
        sem_desejada[ident] = normaliza_acao(spec["action"])
        if sem_atual.get(ident) != normaliza_acao(spec["action"]):
            mudancas.append("%s -> %s" % (fmt_ident(ident), spec["action"]))

    if sem_atual == sem_desejada and os.path.exists(SHORTCUTS):
        print("  OK  atalhos custom ja consistentes (%d bindings)" % len(sem_atual))
        return 0

    blocos = []
    for b, a, _ in mantidos:
        # reemite o texto original do binding (preserva description do dono)
        blocos.append("    %s: %s," % (b.strip(), a))
    for spec in MANAGED:
        blocos.append(emite(spec["mods"], spec["key"], spec["desc"],
                            normaliza_acao(spec["action"])))
    novo = "{\n" + "\n".join(blocos) + "\n}\n"

    for m in mudancas:
        print("  >>  %s" % m)

    if check:
        print("  --  --check: nada escrito. Conteudo que seria gravado:")
        print(novo)
        return 0

    os.makedirs(SHORTCUTS_DIR, exist_ok=True)
    tmp = SHORTCUTS + ".aurora-tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(novo)
    # rename dentro do MESMO diretório: o cosmic-settings-daemon observa o
    # DIRETÓRIO, entao ve o IN_MOVED_TO e recarrega sozinho.
    os.replace(tmp, SHORTCUTS)
    print("  OK  %s atualizado (%d bindings)" % (SHORTCUTS, len(sem_desejada)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
