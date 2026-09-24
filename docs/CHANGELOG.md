# Changelog

## [Não lançado]

### Desativado em 2026-09-24 — o que o MeowSystem pedia emprestado

A mesma regra de 23/09, pelo outro lado: a P37 desativou aqui o que ESCREVIA o
que o MeowSystem escreve; esta desativa o que o MeowSystem LIA daqui para
funcionar. Na máquina de qualquer outra pessoa não há `~/.config/zsh`, e esses
recursos simplesmente não existiam. Do lado de lá, o conferidor
(`tests/portabilidade.sh`, regra 4) passou a recusar `.config/zsh` e `aurora-`
em código que roda, sem escape e sem isenção.

| o quê | o que o MeowSystem fazia com isto | destino | aviso aponta |
|---|---|---|---|
| `scripts/aurora-cosmic-comp-ws.sh` | mandava rodar `--build` (doctor, `forma.sh`) e dependia dele para os patches do compositor existirem | **migrou**: `meow compositor` baixa o fonte da versão instalada, aplica a série de `MeowSystem/patches/`, compila e instala; a versão validada mora em `patches/versao` | `meow compositor` |
| `patches/patches.d/` | nada (a série já morava lá desde 22/09) | **migrou** antes; aqui ganhou a nota de desativado no `LEIA-ME.txt` | — |
| a linha do fastfetch em `env.zsh` | o `fastfetch_logo.sh` a reescrevia (`fastfetch` ↔ `meow-fetch`) e o desinstalador a destrocava | **fica aqui**: a linha agora escolhe sozinha, `meow-fetch` se existir, `fastfetch` se não — o que tira o `command not found` depois de uma desinstalação | — |
| `env.zsh` (`starship init`, `ZSH_THEME`, `FZF_DEFAULT_OPTS`) | o `prompt.sh` lia as três e mandava aplicar aqui o `aurora.patch` | **fica aqui**; o patch saiu do MeowSystem, que agora só diz a linha do `starship init` | — |
| `aurora-cosmic-workspaces.py` | o `areas.sh` o lia como vizinho do `pinned_workspaces` | **saiu de lá**: o script já não existia aqui (medido pela P37); nomear áreas é do MeowSystem desde 07/09 | — |
| `functions/_helpers.zsh` | o `coleta-meowsystem.sh` lia a paleta | **saiu de lá** | — |

**Quem chama o `aurora-cosmic-comp-ws.sh`, medido antes de mexer:** nada neste
repositório (`git grep`), e nesta máquina nenhuma unit nem cópia em
`/usr/local/sbin`. O próprio script documenta que, onde o self-heal do Ritual
está instalado, ele chama `--ensure` de hora em hora como root. Por isso `--ensure`, `--build-auto` e `--compile-only`
saem em silêncio e com 0; `--build`, `--status`, `--restore` e `--podar` dizem
para onde ir e saem 0. O corpo antigo ficou abaixo do `exit`.

**O que NÃO foi para o MeowSystem, de propósito:** o `--ensure` e o auto-build
por timer (lá nada compila nem usa sudo sozinho — o binário é também a tela de
login; quem avisa depois de um `apt` é a linha `patches` do `meow doctor`) e a
reaplicação do night light (a luz quente de lá é o modo de leitura, um patch da
série).

**Ficou no disco, sem ninguém que o leia:** `/var/lib/aurora/` (o `.estado`, os
artefatos `.aurora-ws` e o `.pkg-orig` da a557859) e
`/usr/local/share/aurora/patches.d/`. Nada foi apagado. O MeowSystem grava o
dele em `/var/lib/meowsystem/cosmic-comp/`.

### Desativado em 2026-09-23 — o que brigava com o MeowSystem

A regra do dono, de 23/09: *"tudo do spellbook que entrar em conflito com o
meowsystem, migramos pra cá e desativamos no spellbook"*. Nenhuma função foi
apagada: cada uma virou um aviso curto que aponta o `meow` equivalente e sai sem
escrever. O corpo antigo ficou abaixo do `return` (como no
`aurora-userscripts-apply.sh`), ou no commit `d2d3868` quando era só um ramo.

| o quê | o que escrevia | quem escreve agora | aviso aponta |
|---|---|---|---|
| `rebuild_dracula_theme` (`functions/sistema.zsh`) | build + `install.sh --user` do Dracula_OS-Theme: 4 temas em `~/.local/share/icons`, GTK, hicolor, 30 `.desktop`; com `--activate`, icon/gtk/cursor-theme no gsettings | MeowSystem, lendo de `packs/dracula` (`icones_apps_dracula.sh`, `hicolor.sh`, `cursor.sh`) | `meow pack usar dracula` |
| `_fix_flatpak_icons` (`functions/sistema.zsh`) | `Icon=` de 4 flatpaks, por mapa escrito à mão | MeowSystem (`icones_absolutos.sh`, pelo estado do disco) | `meow aplicar` |
| categoria `tema` do `sistema_restaurar` (`functions/restaurar.zsh`) | gtk/icon/cursor-theme, cursor-size e picture-uri; `dconf load /`; tar do `~/.config/cosmic` inteiro | MeowSystem (`meow.conf` + `meow aplicar`) | `meow aplicar` |
| ramo Dracula_OS-Theme do `santuario` (`functions/projeto.zsh`) | `install.sh --user --all` de lá: gsettings, som, Spotify, Obsidian, qBittorrent, hicolor, lançador, apt hook | MeowSystem | `meow pack usar dracula` |
| `spicetify_instalar` e `scripts/spicetify-setup.sh` | binário, temas, Marketplace, `current_theme`/`color_scheme`, `backup apply` | MeowSystem (manifesto do Spotify, `spicetify_setup.sh` de lá) | `meow apps aplicar spotify` |
| `spicetify_reparar` (só o final) | `restore` + `clear` + `backup apply`, que congelava o tema do MeowSystem como "de fábrica" | virou `spicetify apply`; extensões e custom apps continuam aqui | `meow apps aplicar spotify`, se o apply recusar |

**Quem chama, medido antes de mexer:** nenhuma delas roda sozinha — nenhum hook
do `.zshrc`, timer, unit ou apt hook deste repositório as chama. O
`_fix_flatpak_icons` vem de dentro do `limpar_cache` e do `atualizar_tudo`, à
mão; por isso ali o aviso é uma linha apagada, e não um alerta.

**Ficaram, porque são desta máquina:** `fontes_instalar` (fontes de
compatibilidade com Windows/Mac e o `fonts.conf` de aliases, que o MeowSystem
não escreve), `relatorio` (Liberation Narrow e o `60-relatorio-mec.conf`, em
arquivos próprios), `_reconstruir_caches_icones` (reindexa a partir do disco,
não decide conteúdo), a config do Ghostty, os atalhos, o `aurora-menu-doctor.py`.

**Ficou no disco, sem ninguém que o reconstrua:** `~/.local/share/icons/Dracula-Icones`
(e os irmãos `dracula-icons-main`, `dracula-icons-circle`, `Dracula-Cursor`)
continua servindo de herança enquanto o `meow.conf` pedir
(`ICONES_BASE="Dracula-Icones"`, `CURSOR="Dracula-Cursor"`). Não foi apagado.

**Órfãos fora deste repositório, que a pessoa remove se quiser** (nada foi
removido aqui):

```sh
# 3.400 SVG de 06/10/2025, root; o Spellbook só reindexava a cache
# (_reconstruir_caches_icones). Antes, confira se a tela de login não o usa:
sudo cat /var/lib/cosmic-greeter/.config/cosmic/com.system76.CosmicTk/v1/icon_theme
sudo rm -rf /usr/share/icons/Dracula-Icones /usr/share/icons/Dracula-Cursor

# o apt hook do Dracula_OS-Theme (instalado pelo `install.sh --all` que o
# santuario rodava): 114 passagens no log, a última em 21/09; repõe ícones e
# tenta trocar icon/gtk/cursor-theme depois de todo apt
sudo ~/Desenvolvimento/Dracula_OS-Theme/scripts/instalar_apt_hook.sh --revert
```

### Corrigido em 2026-09-18 — os laços que anunciavam conserto sem consertar

- **`functions/aurora-self-heal.zsh`: o detector do xbindkeys ganhou a guarda de
  sessão que o applier já tinha.** O detector perguntava `pgrep -x xbindkeys` e
  enfileirava o `aurora-gpu-shortcut-apply.sh`; o applier, desde `f4b0dc8`, sai
  0 sob COSMIC porque o atalho foi aposentado de propósito (XGrabKey é X11, a
  tecla nem chegaria). Resultado medido: **7 ocorrências de "1 fix(es)
  aplicado(s)" num log de 25 linhas**, a cada terminal aberto, sem nada mudar.
  A regra que fica: detector e applier que discordam de condição viram laço.

- **`aurora/aurora-menu-doctor.py`: o código de saída passou a responder "há
  trabalho para o `--fix`?", e não "há algo imperfeito?".** O laudo já
  distinguia problema corrigível de suspeita que exige olho humano (a marca
  `!`), mas o `rc` não: `return 1 if laudo.problemas`. Os dois
  `wmclass_suspeito` desta máquina — ONLYOFFICE e Telegram — são exatamente os
  que o `--fix` nunca corrige, e o próprio laudo diz por quê: *"o valor certo se
  observa, não se deduz"*. Com `rc=1` permanente, o self-heal chamava o `--fix`
  para sempre. Os não-corrigíveis continuam impressos: a informação é para o
  humano, só não serve mais de gatilho.

Prova das duas: depois das correções, uma passagem forçada do self-heal (com o
`~/.cache/aurora-self-heal.timestamp` removido) deixou o log **vazio**.

- **`scripts/aurora-zsh-ambiente.sh`: a guarda do binário nativo deixou de
  depender de nome escrito.** Ao versionar o script, o gate `[3/6]` do
  `pre-commit` reescreveu o **argumento** de um `command -v` para um termo
  genérico — um binário que não existe. A checagem virou no-op silencioso e o
  script passou a anunciar "OK" para sempre. O nome agora vem do estado real do
  disco (o symlink de `~/.local/bin` cujo alvo mora em
  `~/.local/share/<nome>/versions/`), e não de uma string que a guarda de
  anonimato precisa reescrever.

### Adicionado em 2026-09-18

- **`Ctrl+Alt+→` e `Ctrl+Alt+←` avançam e voltam o papel de parede**
  (`aurora/aurora-cosmic-shortcuts.py`). O dono procurou isso no menu do botão
  direito da área de trabalho; o item não existe no COSMIC — o `cosmic-files` é
  byte a byte idêntico ao da outra máquina da casa e só conhece
  `change-wallpaper`. O comando (`meow wallpaper proximo|anterior`) já existia e
  só não tinha tecla. `Ctrl+Alt`+seta é a única família de setas livre nos
  defaults do COSMIC.

- **`patches/patches.d/` e os dois scripts em produção entraram no
  versionamento.** A série de cinco patches do `cosmic-comp` (incluindo o
  `blur-cache-textura`, que está no binário instalado), o builder
  `aurora-cosmic-comp-ws.sh` e o `aurora-zsh-ambiente.sh` — este último era
  `ExecStart` de uma unit **ativa e habilitada** e estava fora do repositório:
  um `git clean` derrubaria o guardião.

### Corrigido em 2026-09-17 — três defeitos que se alimentavam

Levantados por auditoria de leitura no nitro-5. Os três tinham a mesma marca:
falhavam em silêncio e o sintoma aparecia longe da causa. Evidência completa em
`~/Desenvolvimento/Migração-OS/auditorias/06-levantamento-2026-09-17/03-spellbook-os.md`.

- **`.zshrc`: `zshexit()` ganhou guarda de interatividade.** Sem `[[ -o
  interactive ]]`, TODA sessão zsh não-interativa disparava um `git push` ao
  sair — inclusive cada chamada da ferramenta Bash de um assistente de código,
  medido em **~1 push a cada 2 segundos**. Dois danos: o push herdava o stdout
  de um shell já morto, e o `echo` de `.githooks/pre-push:308` escrevia nesse
  descritor órfão recebendo EIO (`echo: erro de escrita: Erro de
  entrada/saída`); e o `hooks.log` crescia sem teto. O bloco de *pull* da
  seção 7 sempre teve essa guarda; o de *push* nunca teve.

- **`functions/spellbook-sync.zsh`: a chamada apontava para uma função que não
  existe.** A guarda de 2026-07-31 renomeou `__spellbook_auto_commit` para
  `__spellbook_auto_commit_original` e criou o wrapper `_guardado`, mas a
  chamada ficou com o nome antigo. Resultado: `rc=127` (command not found),
  `had_local` nunca virava `true`, e a máquina de estados **sempre** descia
  para o ramo `"Offline"`. Os estados `"Sincronizado"`, `"Pendente: N
  commit(s)"`, `"Atualizado"` e `"Commit local salvo (sem rede)"` eram
  inalcançáveis. Era isso, e não falta de rede, que o fastfetch mostrava.

- **`functions/spellbook-sync.zsh`: o probe de rede tinha `timeout 2`.** O
  `git ls-remote` real contra o GitHub leva ~2,5 s desta máquina — 5 de 5
  medições deram `rc=124`. O probe reprovava uma rede perfeita e reescrevia o
  cache do fastfetch com o valor errado a cada terminal aberto. Agora são 8 s.

- **`.githooks/_lib.sh`: `hooks.log` ganhou rotação.** Não havia nenhuma, em
  lugar nenhum do repositório; o arquivo crescia desde 2026-03-20 e chegou a
  **8,2 MB / 192.448 linhas**. Agora roda a 2 MiB (`_hook_log_rotacionar`), uma
  geração, comprimida, e silenciosa — qualquer saída ali poluiria o `git push`
  de quem está trabalhando.

### Adicionado
- Navegação "Voltar" entre etapas do TUI (máquina de estados com `--cancel-button`)
- Detecção automática de variáveis de ambiente existentes em todas as etapas do TUI
- Label "Perfil Profissional" no lugar de "Identidade MEC" nos diálogos TUI
- Mensagem de sucesso ao final da instalação
- Módulo `encoding.zsh` — detecção e conversão de encoding (UTF-8, CRLF)
- Módulo `fontes.zsh` — instalação e verificação de fontes de compatibilidade
- Módulo `restaurar.zsh` — backup e restauração de sistema via manifesto
- Etapa de instalação de fontes base (ttf-mscorefonts, Liberation, Noto)
- Etapa de ferramentas de encoding (dos2unix)
- `diagnostico_projeto`: pool de senhas acumulativo — senha digitada uma vez é reutilizada automaticamente em todos os arquivos protegidos subsequentes (PDF, xlsx, xls)
- `diagnostico_projeto`: extração de texto de PDFs via PyMuPDF com suporte a senha
- `diagnostico_projeto`: embedding de imagens no dossiê — base64 inline para arquivos < 1 MB, link relativo para arquivos maiores (JPEG, PNG, GIF, SVG, WebP, AVIF, HEIC e outros)
- `diagnostico_projeto`: suporte a todos os formatos de arquivo de dados (CSV, Excel, JSON, Parquet) com análise via `analisador-dados.py`
- `analisador-dados.py`: suporte a `--passwords-file` para pool de senhas externo

### Corrigido
- Bug de corrupção do `config.local.zsh` na substituição `$HOME` → `${HOME}` via heredoc
- Título do TUI invisível no Cosmic DE (lightcyan → white)
- Skip inteligente do TUI quando configuração existente é detectada
- `diagnostico_projeto`: terminal travava após conclusão (`wc -l < /dev/stdin` bloqueava no TTY; prompt `read -k 1` ficava invisível por estar dentro do redirect)
- `diagnostico_projeto`: saída markdown gerada dentro de code fence externo fazia renderização falhar no GitHub e Obsidian
- `analisador-dados.py`: `pd.read_csv(errors='ignore')` inválido no pandas 3.x — substituído por `on_bad_lines='skip', encoding_errors='ignore'`
- `analisador-dados.py`: arquivos `.xls` (OLE2) não eram descriptografados pelo pool de senhas por falso negativo no `is_xlsx_encrypted` — lógica reescrita para tentar abertura direta primeiro e fallback para pool em qualquer falha

### Alterado
- `diagnostico_projeto`: documento gerado reformulado para renderização GitHub/Obsidian — cabeçalho `#`, seções `##` com separadores `---`, árvore em code block direto, arquivos com labels de tipo (`[PDF]`, `[CSV]`, `[Excel]`, `[Imagem]`, `[Python]`, etc.) nos colapsáveis `<details>`
- `diagnostico.zsh`: acentuação corrigida em toda extensão do arquivo
- `analisador-dados.py`: acentuação corrigida em toda extensão do script

## [1.0.0] - 2023-01-01

### Adicionado
- Configuração zsh modular com 23 módulos de funções
- Menu FZF interativo para projetos dbt/BigQuery
- Controle automático de identidade git por contexto
- Integração com Oh My Zsh
- 9 scripts Python utilitários
- Script de instalação único para Linux
- Templates de configuração local
