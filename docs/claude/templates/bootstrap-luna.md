# Bootstrap — Luna

> Cole o bloco abaixo da linha `---` na sessão Claude viva que revisou as sprints do Luna.
>
> Alternativa automatizada (preferencial): `python3 ~/.config/zsh/scripts/bootstrap-rico-brief.py --projeto luna --saida /home/andrefarias/Desenvolvimento/Luna/VALIDATOR_BRIEF.md`

---

Bootstrap VALIDATOR_BRIEF.md — Luna

Quero capturar TUDO que você aprendeu sobre o projeto Luna. Escreva em `/home/andrefarias/Desenvolvimento/Luna/VALIDATOR_BRIEF.md` seguindo o template em `~/.config/zsh/docs/claude/VALIDATOR_BRIEF_UNIVERSAL_TEMPLATE.md`.

## Contexto do projeto

Luna é agente local-first com TUI Textual complexa. Stack: Python, Ollama, Coqui-TTS (venv_tts Python 3.10), Whisper, moondream (vision), Textual (UI). 49 hooks pre-commit, 18 ADRs com enforcement, RTX 3050 Mobile 4GB (apertado).

## 15 armadilhas críticas (já conhecidas — preencha evidência por item)

1. `think:true` SÓ em qwen3. Qwen2.5 quebra silencioso. Guard: `needs_think = "qwen3" in model.lower()`.
2. KEEP_ALIVE=30m (Sprint 119b). 24h proibido.
3. OLLAMA_MAX_LOADED_MODELS=3 (SLM + moondream + coder simultâneos).
4. Parser JSON tem 4 níveis de fallback — NÃO remover.
5. SmartMemory precisa `warm_up()` no preload.
6. 4 builders de system instruction — regra nova DEVE ir em TODOS.
7. Animações: nomes DEVEM começar com `{Entity}_`.
8. PROIBIDO `qwen3-vl` (50+s CoT até trivial).
9. Sanitizer TTS destrói sentenças — split ANTES da sanitização.
10. Whisper regurgita INITIAL_PROMPT sem fala — `no_speech_prob` gate >0.6.
11. `src/core/__init__.py` — imports de UI com try/except (venv_tts não tem textual).
12. REGISTRY propósitos auto-gerados são LIXO — hook T1 bloqueia.
13. `memory_synthesis` usava `get_slm_elaborate_model` — model swap duplo 6-10s.
14. `identity_validator.py` FALTAVA no streaming path (Sprint 098).
15. `setuptools >= 82` quebra `pkg_resources` no `venv_tts` (manter < 81).

## Modelos Ollama canônicos

- Básico: `qwen2.5:3b` (SLM, ~15 layers GPU ~1487MB)
- Médio: `qwen3:4b` (raciocínio com think:true)
- Vision: `moondream` (~2-3s)
- Code: `qwen2.5-coder:3b`
- **PROIBIDO**: `qwen3-vl`, `llama3.2-vision`
- ARMADILHA: `.env CHAT_LOCAL_MODEL` sobrescreve registry (`config_models.py:105`)

## ADR-018 — GPU EXCLUSIVA com alternância

Hierarquia: TTS(2500MB pico) > Vision(moondream) > Code(qwen2.5-coder:3b) > SLM(qwen2.5:3b ou qwen3:4b).
SLM zona morta 1-14 layers PIOR que CPU puro → forçar 0 OU 15+.
Budget: 3696MB total, ~3400MB utilizável (296MB SO).

## TUI selectors canônicos

- Input: `#main_input` (MultilineInput)
- Mensagens: `.message-container`
- App: `TemploDaAlma` via `src.app.bootstrap.get_service_container()`
- Captura padrão: `bash scripts/tui_tests/capture.sh <area>`
- Critério: `scripts/tui_tests/criteria/<area>.txt`

## Contratos de runtime Luna (canônicos)

- Smoke CLI: `./run_luna.sh --cli-health` (exit 0, <5s)
- TUI completa: `./run_luna.sh` (interativa — rodar em background se validação visual)
- Gauntlet: `./run_luna.sh --gauntlet`
- Gauntlet por fase: `./run_luna.sh --gauntlet --phase <N>`
- Unit tests: NUNCA pytest direto, sempre `./run_luna.sh test`
- `run_test()` NÃO é evidência válida (GUIA_PRODUCAO.md §2)

## Hooks pre-commit críticos

- T1 `check_registry_quality.py` — propósito >=30 chars + verbo de ação + anti-burla
- T3 `registry-guard` — verifica REGISTRY.csv sincronizado
- T3 `sprint-auto-move` — move sprint CONCLUÍDA para `producao/concluidas/`
- `check_visual_evidence.py` — bloqueia commit sem PNG recente se toca UI
- Bypass consciente: `LUNA_SKIP_EVIDENCE=1`, `LUNA_SKIP_REGISTRY_AUDIT=1`

## Arquivos periféricos (acentuação)

- `dev-journey/02-architecture/overview/HISTORICAL_ARMADILHAS.md` — referência obrigatória
- Citações filosóficas em docstrings finais (CLAUDE.md §12)
- Docstrings em `tests/**/*.py`
- Comentários em `src/soul/**/*.py`

## Regras de escrita

- Seja concreto: arquivo, função, linha quando lembrar.
- Não invente. Se não lembra, omita ou marque `<a preencher>`.
- PT-BR direto. Zero emojis. Acentuação correta obrigatória.
- Rodapé: `*Atualizado em <ISO timestamp> por bootstrap-rico (sessão Luna)*`
