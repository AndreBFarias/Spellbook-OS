# AI.md - Protocolo Universal para Agentes de IA
# Regras para qualquer projeto | PT-BR | v4.0

## REGRA DE OURO

Antes de modificar QUALQUER arquivo, leia o codigo existente e entenda o contexto completo.

---

## 1. COMUNICACAO

- PT-BR direto e tecnico (acentuacao correta obrigatoria)
- **ZERO emojis** em codigo, commits, docs, respostas
- Sem formalidades vazias
- Explicacoes tecnicas e concisas

---

## 2. ANONIMATO ABSOLUTO

**PROIBIDO em qualquer arquivo ou commit:**
- Nomes de IAs: "Claude", "GPT", "Gemini", "Copilot", "Anthropic", "OpenAI"
- Atribuicoes: "by AI", "AI-generated", "Gerado por", "Co-Authored-By"
- **NUNCA** incluir `Co-Authored-By:` em commits
- Commits devem ser totalmente limpos e anonimos

**Excecoes permitidas:**
- Strings tecnicas: `api_key`, `provider`, `model`, `config`, `client`
- Documentacao de API de terceiros
- Variaveis de ambiente: `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`

---

## 3. CODIGO LIMPO

- Type hints quando a linguagem suportar
- Arquivo completo, nunca fragmentos
- Nunca use `# TODO` ou `# FIXME` inline (crie issue no GitHub)
- Logging rotacionado obrigatorio (nunca `print()` / `console.log()`)
- Zero comentarios desnecessarios dentro do codigo
- Paths relativos via Path/equivalente (nunca hardcoded absolutos)
- Error handling explicito (nunca silent failures)

### SQL e YAML

- Comentarios de migracao PROIBIDOS inline (ex: `-- migracao: alias para compatibilidade`).
  Se precisar registrar a mudanca, use o corpo do commit.
- Descriptions em `source.yml` devem ser neutras e tecnicas. PROIBIDO codificar
  historico de implementacao (ex: "substituindo tabela X"). Descrever o dado em si.
- Comentarios Jinja (`{# ... #}`) adicionados durante desenvolvimento devem ser
  removidos antes do commit — eles aparecem no codigo-fonte, nao no SQL compilado.

---

## 4. GIT

### Formato de Commit (sempre PT-BR)

```
tipo: descrição imperativa com acentuação correta

# Tipos: feat, fix, refactor, docs, test, perf, chore
```

Exemplos corretos: `migração`, `correção`, `padrões`, `revisão`, `atualização`, `remoção`.

### Proibições

- Zero emojis em mensagens de commit
- Zero menções a IA
- Zero `Co-Authored-By`
- Nunca `--force` sem autorização explícita
- Acentuação PT-BR obrigatória em títulos e corpo do commit
- PR description: uma linha descritiva, sem tabelas, sem bullet points extensos.
  Descrições elaboradas parecem geradas por IA e comprometem o anonimato.
- Antes de abrir PR, verificar o branch target do projeto (ex: `develop`, não `main`).

---

## 5. PROTECOES

- **NUNCA** remover codigo funcional sem autorizacao explicita
- Se usuario pedir refatoracao, perguntar: "Quer adicionar novo ou melhorar o existente?"
- Perguntar antes de alterar arquivos criticos ou de alto impacto

---

## 6. LIMITES

- **800 linhas** por arquivo (excecoes: config, testes, registries)
- Se ultrapassar: extrair para modulos separados, manter imports limpos

---

## 7. GITIGNORE OBRIGATORIO

```gitignore
# Caches
__pycache__/
*.py[cod]
node_modules/
venv/
.venv/

# Logs e dados
logs/
*.log

# Evidencias de IA
Task_Final/
IMPORTANT.md
*.claude.md
*_AI_*.md

# Secrets
.env
*.key
*.pem
.git-credentials

# IDE
.vscode/
.idea/
*.swp

# Sistema
.DS_Store
Thumbs.db
```

---

## 8. PRINCIPIOS

- **Simplicidade** - Codigo simples > codigo "elegante". Evitar over-engineering.
- **Observabilidade** - Tudo tem log. Se nao pode medir, nao pode melhorar.
- **Graceful Degradation** - Falha parcial != crash total. Sempre fallback minimo.
- **Local First** - Tudo funciona offline por padrao. APIs pagas sao opcionais.

---

## 9. META-REGRAS ANTI-REGRESSAO

1. **Sincronizacao N-para-N** - Se um valor existe em N lugares, atualizar TODOS ou nenhum.
2. **Filtros sem falso-positivo** - Todo regex/filtro DEVE ser testado contra inputs que NAO devem casar.
3. **Soberania de subsistema** - Subsistema A NUNCA descarrega/mata recurso de subsistema B.
4. **Observabilidade adaptativa** - Sistema adaptativo sem metrica de saude = bomba-relogio.
5. **Scope atomico** - Bug encontrado ao testar feature Y NAO e fixado inline. Registrar como nova issue.

---

## 10. WORKFLOW

```
1. Ler arquivos relacionados
2. Entender fluxo completo
3. Procurar testes existentes
4. Implementar mantendo compatibilidade
5. Testar incrementalmente
6. Documentar mudancas
```

---

## 11. CHECKLIST PRE-COMMIT

- [ ] Testes passando
- [ ] Zero emojis no codigo
- [ ] Zero mencoes a IA
- [ ] Zero hardcoded values introduzidos
- [ ] Commit message descritivo (PT-BR)
- [ ] Sincronizacao N-para-N verificada
- [ ] Documentacao atualizada se necessario

---

## 12. ASSINATURA

Todo script finalizado recebe uma citacao de filosofo/estoico/libertario como comentario final.

---

*"Codigo que nao pode ser entendido nao pode ser mantido."*
*"Local First. Zero Emojis. Zero Bullshit."*
