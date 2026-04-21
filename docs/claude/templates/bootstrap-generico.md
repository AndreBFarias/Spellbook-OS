# Template genérico — bootstrap VALIDATOR_BRIEF.md

> Use para qualquer projeto novo. Copie o bloco abaixo da linha `---`, substitua
> `<PROJETO>` e `<CAMINHO_ABSOLUTO>` pelos valores reais, cole na sessão Claude
> viva que tem o histórico de expertise daquele projeto.
>
> Para projetos conhecidos com memórias históricas (Luna, Nyx-Code, protocolo-ouroboros),
> prefira o script automatizado: `python3 ~/.config/zsh/scripts/bootstrap-rico-brief.py --projeto <kind>`.

---

Bootstrap VALIDATOR_BRIEF.md — <PROJETO>

Quero capturar TUDO que você aprendeu deste projeto ao longo das sprints que revisamos juntos. Escreva em `<CAMINHO_ABSOLUTO>/VALIDATOR_BRIEF.md` seguindo o template em `~/.config/zsh/docs/claude/VALIDATOR_BRIEF_UNIVERSAL_TEMPLATE.md`.

## Seções CORE (obrigatórias)

- Identidade (nome, linguagem, framework, propósito em 1 linha, tipo-de-projeto)
- Como rodar (smoke, unit, integração, gauntlet, lint)
- Arquitetura essencial (5-10 componentes com responsabilidade e arquivo)
- Checks universais ativados (tabela com as 14 lições)
- Contratos de runtime (comandos canônicos testados neste projeto)
- Arquivos periféricos onde acentuação escapa
- Heurísticas de aritmética (meta de linhas por arquivo, exceções)
- Capacidades visuais aplicáveis

## Seções OPCIONAIS (só com evidência real)

- Padrões recorrentes de bug
- Invariantes não-óbvios
- Decisões arquiteturais chave
- Gambiarras conhecidas / antipatterns
- Cheiros específicos do projeto
- Histórico de sprints relevantes
- Perfis / ambientes (se hardware ou ambiente especial importa)

## Checks universais que sempre rodam

Para cada check, marque aplicável a este projeto e cite comando de teste:

| # | Check | Origem empírica | Aplicável aqui? | Comando |
|---|---|---|---|---|
| 1 | Runtime real (não pytest puro) | Luna feedback_always_test_tui | ? | smoke canônico do projeto |
| 2 | Screenshot UI automático | Luna Sprint 09 | ? | skill validacao-visual |
| 3 | Acentuação periférica | Luna AUD-03 FEN-11 | sim (PT-BR) | `python3 ~/.config/zsh/scripts/validar-acentuacao.py` |
| 4 | Hipótese do revisor empírica | Luna AUD-03 FEN-01d | sim | `rg` antes de aplicar fix |
| 5 | Fix inline vs pular | Luna feedback_fix_inline_never_skip | sim | protocolo explícito |
| 6 | Zero follow-up | Luna + Nyx | sim | Edit-pronto OU sprint-ID |
| 7 | Aritmética de refactor | Luna INFRA-83 ORFEU | ? | `wc -l` + projeção |
| 8 | Plano antes de código | Luna + Nyx | sim | `/planejar-sprint` sempre |
| 9 | Nenhum débito fica pra trás | Nyx feedback_nenhum_debito | sim | SPRINT_ORDER_MASTER.md |
| 10 | Sprints divididas | Luna feedback_split_sprints_deep | sim | rejeitar monolítica |
| 11 | Integração obrigatória | Nyx ADR-013/014 | ? | registry/command/service |
| 12 | Smoke boot real | Nyx BOOT-FIX-01 | ? | smoke comando |
| 13 | Sprint CONCLUÍDA = Gauntlet | Luna ADR-017 | ? | gauntlet por fase |
| 14 | Opus centro inteligência | Luna feedback_opus_review_center | sim | validador-sprint |

## Heurística de validação visual por stack

| Stack | Captura primária | Captura fallback |
|---|---|---|
| TUI Textual / Rich / Curses | `import -window <wid>` via `xdotool search` | scrot terminal inteiro |
| GUI GTK / Qt / Tk | `import -window` via `wmctrl -lx` | claude-in-chrome se app abre browser |
| Web dev local (`npm run dev`, `flask`) | playwright MCP headless | claude-in-chrome se Chrome está aberto |
| Web Chrome já aberto | claude-in-chrome MCP | playwright headless |
| CLI output | scrot terminal | - |
| Library / docs | não aplicável | - |

## Regras de escrita

- Seja concreto: nome de arquivo, função, número de linha quando lembrar.
- Não invente. Se não lembra, omita ou marque `<a preencher>`.
- PT-BR direto. Zero emojis. Acentuação correta obrigatória.
- Rodapé: `*Atualizado em <ISO timestamp> por bootstrap-rico (sessão <PROJETO>)*`

Ao terminar, liste por seção quantas entradas ficaram (ex.: "Padrões de bug: 7, Invariantes: 4, Gambiarras: 2").
