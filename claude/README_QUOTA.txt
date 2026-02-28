=================================================================================
                    CLAUDE QUOTA SYSTEM - INSTALADO
=================================================================================

SEU ALIAS 'cca' AGORA ESTÁ PROTEGIDO!

Antes você usava:
  cca → Claude direto (sem controle)

Agora você usa:
  cca → Claude com quota system (bloqueios automáticos)

=================================================================================
COMANDOS RÁPIDOS
=================================================================================

cq                    Ver quanto você usou esta semana
cca "pergunta"        Usar Claude (protegido automaticamente)
claude-peek file.py   Ver arquivo sem consumir quota
claude-estimate file  Estimar custo antes de ler

=================================================================================
COMO FUNCIONA
=================================================================================

Quando você roda 'cca':

1. [PRE-CHECK] Sistema verifica se você ainda tem quota disponível
   - Se < 10% restante → BLOQUEIA e pede confirmação
   - Se < 20% restante → AVISA mas permite

2. [GUARD] Sistema verifica arquivos que você vai ler
   - Se arquivo > 100KB → BLOQUEIA e sugere alternativas
   - Se arquivo > 50KB → AVISA e pede confirmação

3. [TRACK] Sistema registra quantos tokens você usou
   - Atualiza o contador automaticamente
   - Reseta toda segunda-feira

=================================================================================
EXEMPLO DE USO
=================================================================================

Terminal aberto mostra:
  NVIDIA GPU Ativa: RTX 3050, 470.94, 45°C
  VRAM: 16 MiB / 4096 MiB (0%)
  Claude Quota: 45000 / 500000 tokens (9%) | Cmd: cq
                ^^^^^^^^^^^^^^^^^^^^^^^^^
                Você vê quanto usou sempre!

Antes de trabalhar:
  $ cq
   Uso normal. Ainda tem 455000 tokens.

Durante trabalho:
  $ cca "read big_file.py"
   BLOQUEADO: Arquivo muito grande!
     ALTERNATIVA: grep 'def ' big_file.py

Depois de trabalhar:
  $ cq
  ️ AVISO: 85% do limite usado!

=================================================================================
VOCÊ ECONOMIZA TOKENS ASSIM
=================================================================================

 ANTES (consumia muito):
  cca "what are the functions in this file?"
  cca "explain function X"
  cca "now explain function Y"
  Total: ~5000 tokens

 AGORA (economiza 80%):
  grep "^def " file.py                    # 0 tokens
  cca "explain function X specifically"   # ~500 tokens
  Total: ~500 tokens

=================================================================================
AJUSTAR LIMITES (SE NECESSÁRIO)
=================================================================================

Arquivo: ~/.config/zsh/.claude_guard_config

MAX_FILE_SIZE_KB=100     # Bloqueia arquivos > 100KB
WARN_FILE_SIZE_KB=50     # Avisa arquivos > 50KB

Se você acha muito restritivo, aumente os valores.
Se você quer economizar mais, diminua os valores.

=================================================================================
DOCUMENTAÇÃO COMPLETA
=================================================================================

cat ~/.config/zsh/GUIA_RAPIDO_QUOTA.md
cat ~/.config/zsh/CLAUDE_QUOTA_SYSTEM.md

=================================================================================
TUDO CONTINUA IGUAL, SÓ MAIS SEGURO!
=================================================================================

Use 'cca' como sempre usava.
O sistema trabalha em background protegendo você.

Você só vai notar quando ele:
  - Bloquear algo perigoso (arquivo enorme)
  - Avisar que você está perto do limite
  - Mostrar seu uso no prompt do terminal

Isso é bom! Significa que você NÃO VAI MAIS ESTOURAR O LIMITE.

=================================================================================
