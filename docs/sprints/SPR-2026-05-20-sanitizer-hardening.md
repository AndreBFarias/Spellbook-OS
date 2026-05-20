# SPR-2026-05-20-sanitizer-hardening

> Hardening definitivo de `scripts/universal-sanitizer.py` contra três classes de bug:
> auto-modificação, ataque a libs vendored/minificadas, e falha silenciosa de `ALLOWED_GLYPHS`.

## Contexto

O sanitizer rodou contra si mesmo via pre-commit do autosync em incidentes anteriores
(commit `ecf2b3c` "fix: restaurar variaveis e identidade removidas pelo auto-sanitize",
commit `7ac4fd2` com +36 linhas de alterações fantasma). Também foi confirmado em
2026-05-20 que o sanitizer ALTERA `aurora/userscripts/control-c-ilimitado-ext/lib/html2pdf.bundle.min.js`
quando o pre-commit roda sobre ele, pois a entrada `".min.js"` em `EXCLUDED_EXTENSIONS`
(linha 28) é CÓDIGO MORTO: `pathlib.Path("foo.min.js").suffix == ".js"` (não `.min.js`).

Reprodução confirmada nesta sessão:

- `cp html2pdf.bundle.min.js /tmp/x.js && python3 scripts/universal-sanitizer.py /tmp/x.js`
  reporta `2 emojis removidos` e altera o sha256 do bundle.
- O mesmo sanitizer hoje NÃO modifica uma cópia de si mesmo isoladamente, mas
  `git-add.zsh:25` chama `ruff format` em `*.py` staged logo após o sanitizer, então o
  estado `M scripts/universal-sanitizer.py` no working tree pode misturar dois agentes.

## Escopo (touches autorizados)

Arquivos a modificar:

- `/home/andrefarias/.config/zsh/scripts/universal-sanitizer.py` (único alvo de código)

Arquivos a criar:

- `/home/andrefarias/.config/zsh/scripts/tests/test_sanitizer_invariance.sh` (script de regressão executável)
- `/home/andrefarias/.config/zsh/docs/sprints/SPR-2026-05-20-sanitizer-hardening.md` (este spec)

Arquivos NÃO a tocar:

- `functions/spellbook-sync.zsh` (autosync) — invariante BRIEF §3.
- `functions/git-add.zsh` — wrapper `ga`; CLI signature do sanitizer permanece `argv → arquivos`.
- `functions/mec.zsh:435-450` — chamada via `--check` deve continuar funcionando.
- `hooks/pre-commit:289-298` e `.githooks/pre-commit` — orquestração permanece igual.
- `EXCLUDED_DIRS` set: entrada `"hooks"` deve continuar presente (invariante BRIEF §6 e
  restrição crítica da tabela "NUNCA fazer").
- Frozenset `ALLOWED_GLYPHS` (linhas 76-88): os 11 glifos devem continuar listados na
  forma literal, com mesmas posições e comentários PT-BR. Esta sprint só ADICIONA
  defesas, NÃO remove glifos.

## Acceptance criteria

1. Rodar `python3 scripts/universal-sanitizer.py scripts/universal-sanitizer.py`
   produz exit 0 e `sha256sum` invariante (byte-a-byte idêntico antes/depois).
2. Rodar `python3 scripts/universal-sanitizer.py aurora/userscripts/control-c-ilimitado-ext/lib/html2pdf.bundle.min.js`
   produz exit 0 e `sha256sum` invariante.
3. Arquivo de teste sintético com emoji legítimo (payload Unicode U+1F389, gerado via
   `printf '\xf0\x9f\x8e\x89'` para evitar emoji literal neste documento) AINDA tem o
   emoji removido — funcionalidade primária do sanitizer preservada.
4. Arquivo de teste sintético contendo todos os 11 glifos do `ALLOWED_GLYPHS` permanece
   invariante após sanitização (regressão contra incidente `ecf2b3c`).
5. `python3 -m py_compile scripts/universal-sanitizer.py` exit 0.
6. `python3 scripts/validar-acentuacao.py --paths scripts/universal-sanitizer.py` exit 0.
7. Script `scripts/tests/test_sanitizer_invariance.sh` é executável (chmod +x) e
   exit 0 numa execução fresca.
8. `git status --porcelain` após a sprint contém apenas os 2 arquivos do escopo
   (sanitizer + teste + spec); nenhum touch lateral.

## Invariantes a preservar (do BRIEF)

- Princípio "zero funções removidas" (BRIEF §8): `sanitize_file`, `is_excluded`,
  `is_binary`, `get_git_identity`, `_strip_emojis_preserving_allowed`, `main` —
  todas devem continuar exportadas com mesma assinatura. Esta sprint só ADICIONA
  funções auxiliares.
- PT-BR estrito (BRIEF §9) em qualquer docstring/comentário/log novo.
- `EXCLUDED_DIRS` mantém `"hooks"` (BRIEF tabela "NUNCA fazer").
- CLI signature inalterada: `python3 universal-sanitizer.py <arquivo1> [arquivo2] ...`;
  flags atualmente aceitas (`--check` referenciado em `mec.zsh:444`) devem continuar
  sendo aceitas como no-op ou interpretadas como modo silencioso compatível.
- Exit code 0 mesmo quando nenhum arquivo é alterado (compatibilidade com `git-add.zsh:18`).

## Plano de implementação

Passo 1 — Auto-exclusão por realpath:

- Definir constante `SANITIZER_REALPATH = os.path.realpath(__file__)` em escopo de módulo.
- Em `is_excluded(filepath)`, adicionar como primeira checagem após resolver `parts`:

  ```python
  try:
      if os.path.realpath(filepath) == SANITIZER_REALPATH:
          return True
  except OSError:
      pass
  ```

  Justificativa: cobre o caso em que o sanitizer é chamado com path relativo, absoluto,
  ou via symlink. `realpath` resolve tudo para inode canônico.

Passo 2 — Fix da causa raiz de `.min.js` / `.min.css` / `.metainfo.xml`:

- O `EXCLUDED_EXTENSIONS` set (linha 20-32) tem entradas multi-ponto (`".min.js"`,
  `".min.css"`, `".metainfo.xml"`) que NUNCA casam contra `Path(filepath).suffix` (que
  só retorna o último ponto). Confirmado:
  `Path("html2pdf.bundle.min.js").suffix == ".js"` (não `.min.js`).
- Solução cirúrgica: introduzir checagem secundária baseada em match de substring do
  nome. Implementação preferida:

  ```python
  EXCLUDED_NAME_SUFFIXES = (
      ".min.js", ".min.css", ".bundle.js", ".bundle.css",
      ".metainfo.xml",
  )
  # dentro de is_excluded():
  name_lower = path.name.lower()
  if any(name_lower.endswith(s) for s in EXCLUDED_NAME_SUFFIXES):
      return True
  ```

- Remover de `EXCLUDED_EXTENSIONS` as entradas mortas `.min.js` e `.min.css`
  (`.map` permanece como suffix-único válido: `Path("x.map").suffix == ".map"`).
  Apenas `.min.js` e `.min.css` saem dali e entram em `EXCLUDED_NAME_SUFFIXES`.

Passo 3 — Allowlist de paths vendored:

- Adicionar tupla `EXCLUDED_PATH_SUBSTRINGS`:

  ```python
  EXCLUDED_PATH_SUBSTRINGS = (
      "/userscripts/",  # qualquer userscript Chrome
      "/lib/",          # subdiretório lib/ comum em vendored
      "/vendor/",
      "/third_party/",
      "/node_modules/",  # belt-and-suspenders junto com EXCLUDED_DIRS
  )
  ```

  Em `is_excluded`, após as checagens atuais, testar `any(s in str(path) for s in EXCLUDED_PATH_SUBSTRINGS)`.
- Decisão de design: incluir `"/lib/"` é defesa em camadas junto com o suffix-glob
  da etapa 2 (lib vendored + minificado).

Passo 4 — Auditoria do pipeline interno (hipóteses do contexto):

- Hipótese A (segundo regex além de `EMOJI_RE`): FALSA. `SECRET_PATTERNS`, `COAUTHOR_RE`,
  `AI_ARTIFACT_RE` (linhas 105-125) não casam contra os glifos canônicos.
- Hipótese B (normalização Unicode NFKC/NFKD/NFC): FALSA. O sanitizer atual não chama
  `unicodedata.normalize`.
- Hipótese C (strip de non-printable): FALSA. `line.rstrip()` (linha 201) só remove
  whitespace trailing; não afeta glifos no meio.
- Hipótese D (ASCII-fy / transliteração): FALSA. Nenhum `encode('ascii', ...)` no
  arquivo.
- Hipótese E (CONFIRMADA): regressão histórica em `ecf2b3c` foi causada por estado
  ANTIGO do sanitizer (sem `_strip_emojis_preserving_allowed` e sem `ALLOWED_GLYPHS`).
  Hoje, com `_strip_emojis_preserving_allowed` em vigor (linhas 91-103), o sanitizer
  NÃO removeria os glifos canônicos numa cópia sua. Reprodução nesta sessão confirma:
  `sha256sum` de cópia de `universal-sanitizer.py` é invariante após executar
  sanitização contra ela mesma. Conclusão: a causa raiz da auto-mutilação foi corrigida
  na adoção de `ALLOWED_GLYPHS`; esta sprint adiciona DEFESA EM PROFUNDIDADE
  (auto-exclusão por realpath) para o caso futuro de a regex mudar novamente.

Passo 5 — Teste de regressão executável:

- Criar `/home/andrefarias/.config/zsh/scripts/tests/test_sanitizer_invariance.sh`
  com shebang `#!/usr/bin/env bash`, `set -euo pipefail`, e os 6 testes do
  proof-of-work abaixo. Emoji literal de teste DEVE ser gerado via `printf`
  com bytes UTF-8 (jamais escrever emoji direto no source), por exemplo
  `printf '\xf0\x9f\x8e\x89'` para U+1F389. Saída em formato `[OK] ...` /
  `[FAIL] ...` em PT-BR.
- `chmod +x` no final.

Passo 6 — Smoke das integrações:

- `bash -n hooks/pre-commit` (não foi modificado, mas confirmar que sintaxe não quebrou).
- Simular `ga()`: `git add scripts/universal-sanitizer.py && git diff --cached --name-only | xargs python3 scripts/universal-sanitizer.py` e confirmar exit 0 sem alterar nada.

## Aritmética (sem meta numérica de linhas)

Esta sprint NÃO declara meta de redução de linhas. Adições estimadas:

- `SANITIZER_REALPATH` constante: +1 linha.
- Bloco de auto-exclusão em `is_excluded`: +4 linhas.
- `EXCLUDED_NAME_SUFFIXES` tupla: +5 linhas (com docstring inline).
- Checagem de suffix composto: +2 linhas.
- `EXCLUDED_PATH_SUBSTRINGS` tupla: +6 linhas.
- Checagem de substring de path: +2 linhas.
- Remoção de `.min.js` e `.min.css` de `EXCLUDED_EXTENSIONS`: -2 linhas.
- Comentários explicativos PT-BR: aproximadamente 6 linhas.

Total estimado: `262 + 24 = 286 linhas`. Sem meta restritiva.

Script de teste novo: aproximadamente 70 linhas bash.

## Testes

Adicionar:

- `scripts/tests/test_sanitizer_invariance.sh` — 6 casos cobrindo proof-of-work.

Cobertura:

- Invariância de auto-aplicação (caso 2 do proof-of-work).
- Invariância da lib vendored (caso 3).
- Funcionalidade preservada — emoji removido (caso 4).
- Preservação dos 11 glifos `ALLOWED_GLYPHS` (caso 5).
- Compilação válida do Python (caso 1).
- Escopo cirúrgico via `git status` (caso 6).

Baseline: FAIL_BEFORE atual = 2 (sanitizer altera html2pdf bundle; status no working
tree tem `M scripts/universal-sanitizer.py` por `ruff format`).
Esperado FAIL_AFTER = 0.

## Proof-of-work esperado

Executor DEVE rodar todos estes comandos LITERALMENTE e colar a saída no relatório
da sprint. Falha em qualquer um bloqueia "sprint pronta".

```bash
# 1. Syntax check
python3 -m py_compile scripts/universal-sanitizer.py

# 2. Invariância byte-a-byte do próprio sanitizer
H1=$(sha256sum scripts/universal-sanitizer.py | cut -d' ' -f1)
python3 scripts/universal-sanitizer.py scripts/universal-sanitizer.py
H2=$(sha256sum scripts/universal-sanitizer.py | cut -d' ' -f1)
[[ "$H1" == "$H2" ]] && echo "OK invariante" || { echo "FAIL: sanitizer alterou a si mesmo"; exit 1; }

# 3. Invariância da lib vendored
H3=$(sha256sum aurora/userscripts/control-c-ilimitado-ext/lib/html2pdf.bundle.min.js | cut -d' ' -f1)
python3 scripts/universal-sanitizer.py aurora/userscripts/control-c-ilimitado-ext/lib/html2pdf.bundle.min.js
H4=$(sha256sum aurora/userscripts/control-c-ilimitado-ext/lib/html2pdf.bundle.min.js | cut -d' ' -f1)
[[ "$H3" == "$H4" ]] && echo "OK invariante vendored" || { echo "FAIL: sanitizer alterou vendored"; exit 1; }

# 4. Teste positivo: sanitizer ainda remove emoji legítimo
#    (emoji gerado via bytes UTF-8 para evitar literal neste documento)
TESTFILE=$(mktemp --suffix=.py)
EMOJI=$(printf '\xf0\x9f\x8e\x89')
printf 'x = "ola %s"\n' "$EMOJI" > "$TESTFILE"
python3 scripts/universal-sanitizer.py "$TESTFILE"
if grep -q "$EMOJI" "$TESTFILE"; then
    echo "FAIL: emoji não removido"; rm "$TESTFILE"; exit 1
else
    echo "OK função preservada"
fi
rm "$TESTFILE"

# 5. Preservação dos 11 glifos canônicos em texto legítimo
TESTFILE2=$(mktemp --suffix=.py)
printf 'glyphs = "\xe2\x97\x8b\xe2\x97\x90\xe2\x97\x8f\xe2\x97\x86\xe2\x97\x87\xe2\x96\xb6\xe2\x96\xbc\xe2\x96\xb8\xe2\x97\xbc\xe2\x97\xbb\xe2\x86\x97"\n' > "$TESTFILE2"
H5=$(sha256sum "$TESTFILE2" | cut -d' ' -f1)
python3 scripts/universal-sanitizer.py "$TESTFILE2"
H6=$(sha256sum "$TESTFILE2" | cut -d' ' -f1)
[[ "$H5" == "$H6" ]] && echo "OK glifos canonicos preservados" || { echo "FAIL: ALLOWED_GLYPHS quebrado"; exit 1; }
rm "$TESTFILE2"

# 6. git status limpo (nenhum arquivo modificado em disco fora do esperado)
git status --porcelain | grep -v '^?? ' | grep -v 'universal-sanitizer.py' && { echo "FAIL: touches fora do escopo"; exit 1; } || echo "OK escopo cirurgico"
```

Adicional do BRIEF:

```bash
# 7. Validação de acentuação PT-BR (BRIEF §9)
python3 scripts/validar-acentuacao.py --paths scripts/universal-sanitizer.py

# 8. Diff contra HEAD para confirmar que sprint não introduziu auto-modificação
git diff HEAD scripts/universal-sanitizer.py | head -200

# 9. Smoke do shell (BRIEF check #12)
zsh -ic 'true'

# 10. Smoke do wrapper ga via simulação (não real-staging, só dry-run)
zsh -c 'source ~/.config/zsh/.zshrc; type ga | head -3'

# 11. Script de regressão completo
bash scripts/tests/test_sanitizer_invariance.sh
```

Hipóteses verificadas via grep (lição 4):

- `SANITIZER_REALPATH`, `EXCLUDED_NAME_SUFFIXES`, `EXCLUDED_PATH_SUBSTRINGS` são
  identificadores NOVOS — confirmar ausência prévia: `rg -n 'SANITIZER_REALPATH|EXCLUDED_NAME_SUFFIXES|EXCLUDED_PATH_SUBSTRINGS' .` deve retornar vazio antes da sprint, e somente no novo código depois.
- `_strip_emojis_preserving_allowed`, `ALLOWED_GLYPHS`, `EMOJI_RE`, `is_excluded`,
  `sanitize_file`, `EXCLUDED_DIRS`, `EXCLUDED_EXTENSIONS`, `EXCLUDED_NAMES` —
  confirmados presentes em `scripts/universal-sanitizer.py` linhas 13, 20, 34, 41,
  76, 91, 128, 166.

## Riscos e não-objetivos

Não-objetivos (escopo FORA desta sprint — abrir nova sprint se aparecer durante execução):

- Refatorar `git-add.zsh` ou separar `ruff format` do sanitizer call.
- Mudar `hooks/pre-commit` ou `.githooks/pre-commit`.
- Adicionar suporte a `--check` real (hoje é no-op em `mec.zsh:444`); manter compat
  no-op.
- Adicionar logging em arquivo (`~/.local/state/sanitizer.log`) — não pedido.
- Refatorar `EMOJI_RE` para excluir explicitamente o range Geometric Shapes
  `U+25AA-U+25FE` (alternativa mais agressiva, mas mudaria semântica para terceiros).
- Migrar para AST-aware diff (não rodar regex contra strings literais Python).

Riscos cobertos:

- Se executor remover entrada `"hooks"` de `EXCLUDED_DIRS` por engano: bloqueado pelo
  acceptance criterion #8 e proof-of-work #8 (diff inspection).
- Se executor remover algum glifo do `ALLOWED_GLYPHS`: bloqueado pelo proof-of-work #5.
- Se executor quebrar CLI signature: bloqueado pelo proof-of-work #10 (smoke do `ga`).

Riscos NÃO cobertos por esta sprint (aceitos):

- `ruff format` em `git-add.zsh:25` ainda pode alterar formatação do sanitizer fonte
  após edits manuais. Isso é problema separado — escopo fora.
- Userscripts JS fonte (não-vendored, sem `/lib/` no path) ainda serão sanitizados.
  Aceito; sprint não pretende cobrir todo cenário userscript.

## Touches permitidos vs proibidos (checklist)

Permitidos:

- [x] `scripts/universal-sanitizer.py` — modificar conforme plano passos 1-4.
- [x] `scripts/tests/test_sanitizer_invariance.sh` — criar.
- [x] `docs/sprints/SPR-2026-05-20-sanitizer-hardening.md` — este arquivo.

Proibidos:

- [ ] Qualquer arquivo em `functions/`.
- [ ] Qualquer arquivo em `hooks/` ou `.githooks/`.
- [ ] Qualquer arquivo em `aurora/` (incluindo o html2pdf.bundle.min.js — sprint quer
      provar INVARIÂNCIA, não modificá-lo).
- [ ] `VALIDATOR_BRIEF.md` (validador atualiza no fim da sprint, não executor).
- [ ] `.zsh_secrets`, `vault/`, `~/.local/state/*` (invariantes BRIEF §2).
- [ ] `EXCLUDED_DIRS` perdendo a entrada `"hooks"` (BRIEF tabela "NUNCA fazer").
- [ ] `ALLOWED_GLYPHS` perdendo qualquer um dos 11 glifos atuais.

## Referências

- BRIEF: `/home/andrefarias/.config/zsh/VALIDATOR_BRIEF.md` (seções CORE §6, §8;
  histórico de incidentes; tabela "NUNCA fazer" linhas 147-148).
- Precedente histórico: commit `ecf2b3c "fix: restaurar variaveis e identidade
  removidas pelo auto-sanitize"` e `7ac4fd2` (auto: sync com +36 linhas suspeitas).
- Memória do projeto: `~/.claude/projects/-home-andrefarias--config-zsh/memory/sprint_audit_2026_05_20.md`.
- Call sites do sanitizer: `functions/git-add.zsh:18`, `functions/mec.zsh:444`,
  `hooks/pre-commit:293`.
