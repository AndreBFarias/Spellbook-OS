# Changelog

## [Não lançado]

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
