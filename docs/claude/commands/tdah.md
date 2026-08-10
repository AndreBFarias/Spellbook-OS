---
description: Liga o formato de resposta direto (ação primeiro, sem preâmbulo) nesta sessão e nas seguintes
argument-hint: [ligar|desligar|estado]
---

Controle o formato de resposta direto.

`$ARGUMENTS` vazio equivale a `ligar`.

## Passos

### 1. Descobrir o arquivo-flag

É `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.i-have-adhd-always`. A presença dele é o
que faz o hook de início de sessão injetar o conjunto de regras.

### 2. Agir conforme o argumento

**`ligar`** — crie o arquivo-flag e, a partir de agora **nesta mesma conversa**,
passe a responder no formato: ação primeiro, passos numerados, sem preâmbulo e
sem conclusão de cortesia, máximo 5 itens por lista, tangentes cortadas.

Isto é o ponto do comando: o hook só age na abertura da sessão, então ligar pelo
terminal não muda a conversa em andamento. Aqui você muda as duas coisas — o
comportamento imediato e a persistência.

**`desligar`** — remova o arquivo-flag e volte ao formato normal já nesta
conversa.

**`estado`** — apenas informe se o arquivo existe, sem alterar nada.

### 3. Confirmar

Diga em uma linha o que mudou, e deixe claro que o efeito é imediato aqui **e**
persistente nas próximas sessões.

## Observações

- A seção 5 do `GUIDE.md` é a árbitra: a forma vem daqui, o conteúdo didático
  continua permitido, mas condensado em no máximo um bloco curto ao final.
- Equivalentes de terminal: `ativar_tdah` e `desativar_tdah`. Aqueles só valem
  da próxima sessão em diante.
