---
description: Trabalho visual com a skill hallmark como direção principal, em vez do padrão templateão de IA
argument-hint: [o que construir ou revisar]
---

Faça trabalho visual usando `hallmark` como direção de design principal.

## Passos

### 1. Invocar a skill

Invoque a skill `hallmark` **antes** de escrever qualquer marcação ou estilo.
Não pule esta etapa por achar o pedido pequeno: a skill existe justamente para
impedir a queda nos padrões que todo modelo produz por inércia.

### 2. Aplicar a hierarquia

- `hallmark` é a direção principal, inclusive dentro do modo `/design`
- `frontend-design` entra só no que `hallmark` não cobrir
- havendo conflito entre as duas, `hallmark` vence

Esta ordem está na seção 6 do `GUIDE.md`. Ela é necessária porque a descrição da
skill não menciona o modo `/design` — sem a regra, o acionamento ali não
acontece sozinho.

### 3. Executar o pedido

`$ARGUMENTS` traz o que construir ou revisar. Vazio, pergunte o que é para
fazer antes de propor qualquer coisa.

### 4. Validar

Se o resultado for visível, capture evidência visual conforme a skill
`validacao-visual` e mostre. Design sem prova de como ficou não está entregue.

## Observações

- A skill traz `references/` com temas, macroestruturas e catálogo de
  componentes. Leia sob demanda, arquivo a arquivo — não carregue tudo.
- Equivalente de terminal: `design_humano`, que abre a sessão já orientada.
