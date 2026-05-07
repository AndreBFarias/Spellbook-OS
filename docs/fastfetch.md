# Fastfetch — Cabeçalho visual do terminal

Configuração canônica em `~/.config/zsh/fastfetch/config.jsonc`. Symlinkada para `~/.config/fastfetch/` pelo `install.sh` (etapa `_step_fastfetch_symlink`).

## O que entrega

- Logo Pop_OS clássico, deslocado 6 linhas para baixo (`logo.padding.top: 6`) — info no topo, logo logo abaixo.
- Title `usuário@host` e separator de dashes em **magenta bold**.
- Labels (`SO:`, `Memória:`, `Disco:`, …) em **magenta bold**.
- Argumentos das keys entre parens (`(/home)`, `(24GL600F)`, `(enx…)`, `(AP21D8M)`) em magenta bold (herdam cor da key).
- Values em branco normal.
- Tags em values entre parens laranja Dracula: `(Dedicada)`, `(Integrada)`, `(Conectado)`, `(Desconectado)`, `(Externo)`, `(Embutido)`, `(GTK2/3/4)`, …
- Percentuais com cor dinâmica via threshold nativo do fastfetch: verde < 50%, amarelo 50–80%, vermelho ≥ 80%.
- Linha `CPU: <nome> (N cores) @ <freq> | <temp>°C` via sensor `k10temp` (AMD) / `coretemp` (Intel), com cor dinâmica na temperatura via threshold do fastfetch. Habilitada por `"temp": true` no módulo `cpu`.
- Linha custom `GPU: NVIDIA … | VRAM …/… (N%)` via `nvidia-smi` (módulo `command`), com `(N%)` em laranja.
- Linha `Spellbook-OS: <status>` lendo `/tmp/spellbook_status_$(id -u)` populado pelo `spellbook_sync_pull` (background).
- Quebra de linha entre fim do bloco e o prompt (echo final em `env.zsh`).

## Tradução PT-BR

**Labels** (no `config.jsonc`, via campo `key`):

| Inglês | PT-BR |
|---|---|
| OS | SO |
| Host | Modelo |
| Uptime | Tempo Ativo |
| Packages | Pacotes |
| Display | Tela |
| DE | Ambiente |
| WM Theme | Tema WM |
| Theme | Tema |
| Icons | Ícones |
| Font | Fonte |
| Terminal Font | Fonte Terminal |
| Memory | Memória |
| Disk | Disco |
| Local IP | IP Local |
| Battery | Bateria |
| Locale | Idioma |

Mantidos em inglês (nomes técnicos): `Kernel`, `Shell`, `WM`, `Cursor`, `Terminal`, `CPU`, `GPU 1/2`, `Swap`.

**Tags em values** (via pipe sed em `env.zsh`):

| Inglês | PT-BR |
|---|---|
| [Discrete] | (Dedicada) |
| [Integrated] | (Integrada) |
| [AC Connected] | (Conectado) |
| [AC Disconnected] | (Desconectado) |
| [External] | (Externo) |
| [Built-in] | (Embutido) |
| [outras `[X]` genéricas] | (X) |

## Pipeline em `env.zsh`

```bash
clear
fastfetch --pipe false | sed -E $'<traduções> + <colorização>'
echo
```

- `--pipe false` força ANSI mesmo em pipe (default do fastfetch é desabilitar cores quando stdout não é TTY — flag documentada no README oficial: *"force fastfetch to run in colorful mode"*).
- O sed traduz tags conhecidas para PT-BR e migra todas de `[]` para `()` colorido em laranja Dracula (`\e[38;2;255;184;108m`).
- `echo` final: quebra de linha entre o bloco e o prompt.

## Quirks documentados

- **`{percentage}` já vem com `%`**: format `({percentage})` produz `(65%)`. Format `({percentage}%)` produz `(65%%)` (duplicado). Vale também para `{size-percentage}`, `{capacity}`.
- **`logo.padding.top` desce só o logo**, não o info. Usar `printf '\n%.0s' {1..N}` antes do fastfetch desce ambos (errado).
- **`\033` em replacement de GNU sed** é interpretado como `\0` (match completo) + literal `33`. Usar `\e` em zsh ANSI-C quoting (`$'...'`) — vira ESC byte literal antes do sed receber.
- **Regex de bracket precisa excluir `[` do conteúdo** (`[^][\\x1b]+`) para não capturar `[m` de sequências ANSI vizinhas. Por isso a colorização migrou para parens — `()` não aparecem em ANSI, mais seguro.
- **`status` é variável reservada em zsh** — usar `msg` ou outro nome em `local <nome>="$1"`.

## Arquivos

| Arquivo | Função |
|---|---|
| `fastfetch/config.jsonc` | Config canônico (logo, padding, color.keys, color.title, modules) |
| `env.zsh:78` | Pipeline `clear → fastfetch --pipe false | sed → echo` |
| `functions/spellbook-sync.zsh` | Background sync com cache em `/tmp/spellbook_status_$(id -u)` |
| `install.sh` (`_step_fastfetch_symlink`) | Cria symlink `~/.config/fastfetch -> ~/.config/zsh/fastfetch` |

## Performance

- Baseline pré-iter1: ~549 ms (`zsh -i -c exit`).
- Atual: ~460–470 ms.
- Economia vem de: lazy-load (`pyenv`, `gh`, `nvm`), spellbook em background com `&!`, sed simples (< 5 ms).
