# SPR-2026-08-07-freeze-pressao-memoria

Conter o consumo de memória dos aplicativos Flatpak em slices systemd, recalibrar os tetos para uma máquina de 14,81 GiB e alertar por PSI antes do thrashing. Quatro fases (F1 a F4) ordenadas por risco crescente contra ganho.

Este freeze NÃO é o mesmo do `DOSSIE-2026-07-09-termico-e-freeze.md`. São dois modos de falha distintos e a máquina só tinha defesa para o segundo:

| Modo de falha | Data | Assinatura | Defesa existente |
|---|---|---|---|
| Hang de display/compositor AMD | 2026-07-09 | Cursor mexe, tela não redesenha, PSI = 0.00, 5,5 GB disponíveis | Ctrl+Alt+0 (`aurora-gpu-revive`) + `aurora-compositor-heartbeat.sh` |
| Thrashing de paginação | 2026-08-07 | Tela para de responder porque o compositor espera páginas voltarem do swap | NENHUMA |  <!-- noqa-acento -->

---

## Contexto

Em 2026-08-07 o usuário relatou "freeze na tela". O diagnóstico ao vivo mostrou o Microsoft Edge (Flatpak `com.microsoft.Edge` 151.0.4129.59) com **32 processos e 6,21 GiB de RSS** numa máquina de 14,81 GiB, com apenas 732 MiB livres e 7,6 GiB já paginados na zram. Depois de `flatpak kill com.microsoft.Edge`, a memória usada caiu de 10 GiB para 8,7 GiB e o disponível subiu de 2,8 GiB para 4,8 GiB.

O sintoma é thrashing de paginação: o compositor não consegue redesenhar porque fica bloqueado esperando páginas retornarem da swap. A causa é ausência de **teto** no consumidor, e ela se decompõe em duas falhas independentes, ambas dentro de infraestrutura que **já existe** neste repositório.  <!-- noqa-acento -->

### Falha 1 — as slices de memória são órfãs para Flatpak

Cgroup do Edge capturado em runtime durante o incidente:

```
/proc/264350/cgroup:
0::/user.slice/user-1000.slice/user@1000.service/app.slice/app-flatpak-com.microsoft.Edge-264147.scope
memory.high    = max
memory.max     = max
memory.current = 449245184
```

`aurora/units/browser.slice` define `MemoryHigh=8G / MemoryMax=10G / MemorySwapMax=4G / CPUWeight=80`, mas nada aplica isso ao Edge. A função `aplica_slice_override()` (`aurora/aurora-bootstrap.sh:280-294`) lê apenas `src="/usr/share/applications/${app}.desktop"` e é chamada só para apps nativos (`aurora-bootstrap.sh:297-306`): `google-chrome`, `firefox`, `firefox-esr`, `brave-browser`, `chromium`, `slack`, `discord`, `code`, `cursor`, `zoom`. Os Flatpaks exportam seus `.desktop` em `/var/lib/flatpak/exports/share/applications/` e `~/.local/share/flatpak/exports/share/applications/`, caminhos que a função nem consulta.

Confirmado nesta sessão: **os 23 aplicativos Flatpak da máquina rodam sem qualquer teto de memória.**

### Falha 2 — earlyoom não prioriza o maior comilão

`/etc/default/earlyoom` (idêntico a `aurora/earlyoom.default`, earlyoom v1.6.2, PID 867, `active`):

```
--prefer '^(chrome|chromium|firefox|slack|zoom|electron|discord|teams|code|cursor|VSCodeHelper)$'
```

O regex é ancorado e **não contém `msedge`**, que é o `comm` real do processo. O consumidor número um da máquina é exatamente o que o OOM killer não prioriza matar.

---

## Investigação realizada (fatos medidos em 2026-08-07)

Toda afirmação abaixo foi verificada com comando nesta sessão. Nada é suposição.

| Ponto | Comando | Resultado |
|---|---|---|
| RAM total | `grep MemTotal /proc/meminfo` | `15531228 kB` = 14,81 GiB = 15167 MiB |
| Swap | `swapon --show` | `/dev/zram0` 14,8G prio 1000 + `/dev/dm-0` 8,4G prio -1 (0B em uso) |
| Compressão zram | `zramctl` | zstd, DATA 5,3G para COMPR 1,3G (razão aproximada 4,1x) |
| sysctl vivos | `sysctl vm.swappiness ...` | `swappiness=180`, `vfs_cache_pressure=50`, `watermark_scale_factor=125`, `page-cluster=0` |
| Flatpaks instalados | `flatpak list --app` | 23 aplicativos |
| App-ids com hífen | `flatpak list --app --columns=application \| grep -c -e '-'` | **0** (importante para F2, ver abaixo) |
| Chrome nativo tem teto? | `systemctl --user show run-re99...scope -p Slice` | `Slice=browser.slice` — o mecanismo atual **funciona para nativos** |
| Teto efetivo da browser.slice | `cat .../browser.slice/memory.max` | `10737418240` (10G), `memory.high` = 8G, `memory.current` = 1,05 GiB |
| Flatpak tem teto? | `systemctl --user show app-flatpak-com.rtosta.zapzap-15710.scope` | `Slice=app.slice`, `MemoryHigh=infinity`, `MemoryMax=infinity`, `Transient=yes` |
| Quem cria o scope do Flatpak | `strings $(command -v flatpak) \| grep -E 'app-flatpak\|StartTransientUnit'` | O binário do Flatpak 1.14.6 contém `app-flatpak-%s-%d.scope` e `StartTransientUnit` — **o próprio Flatpak cria o scope** |
| Flatpak passa `Slice=`? | mesma varredura de strings | Nenhuma propriedade `Slice` — o gerenciador de usuário aplica o padrão `app.slice` |
| Quem mora em app.slice | `ls /sys/fs/cgroup/.../app.slice/` | `app-gnome-aurora\x2dcompositor\x2dhb-4180.scope`, `app-gnome-ulauncher`, `app-gnome-touchegg`, `app-org.gnome.Terminal.slice`, doze serviços `dbus-*` do GNOME, todos os `app-flatpak-*` |
| PSI de memória saudável | `cat /proc/pressure/memory` | `some avg10=0.00 avg60=0.00 avg300=0.00-0.02`; `full` idêntico |
| PSI de I/O logo após o kill | `cat /proc/pressure/io` | `some avg300=17.15` decaindo para `13.58` — o rastro do thrashing |
| earlyoom | `earlyoom --help` | v1.6.2; `--prefer REGEX` soma 300 ao `oom_score`; `--avoid` subtrai 300 |
| Formato do mem-snapshot | `head -1 /var/log/mem-snapshot.log` | `ts,mem_total_mib,mem_avail_mib,swap_total_mib,swap_used_mib,psi_some_avg10,psi_some_avg60,top15` (8 colunas, 4367 linhas) |
| Units de memória ativas | `systemctl is-active ...` | `product-oom-watchdog.service` active, `mem-snapshot.timer` active, `aurora-health.timer` active |

### Probe decisiva: drop-in por prefixo alcança scope transiente

O ponto crítico de toda a sprint era saber se dá para limitar um scope que o próprio Flatpak cria. Foi feita uma probe controlada e removida ao final (nenhum resíduo, confirmado com `ls`).

Probe 1 — drop-in `~/.config/systemd/user/aurora-dropin-probe-.scope.d/10-probe.conf` com `[Scope] MemoryHigh=1G / MemoryMax=2G`, seguido de `systemd-run --user --scope --unit=aurora-dropin-probe-x.scope -- sleep 12`:

```
Slice=app.slice
MemoryHigh=1073741824
MemoryMax=2147483648
DropInPaths=/home/andrefarias/.config/systemd/user/aurora-dropin-probe-.scope.d/10-probe.conf
Transient=yes
```

Probe 2 — segundo drop-in num prefixo mais raso (`aurora-dropin-.scope.d/20-probe-slice.conf`) contendo `[Scope] Slice=browser.slice / MemorySwapMax=1G`, com o scope `aurora-dropin-probe-y.scope`:

```
Slice=browser.slice
MemoryHigh=1073741824
MemoryMax=2147483648
MemorySwapMax=1073741824
DropInPaths=.../aurora-dropin-probe-.scope.d/10-probe.conf .../aurora-dropin-.scope.d/20-probe-slice.conf
ControlGroup=/user.slice/user-1000.slice/user@1000.service/browser.slice/aurora-dropin-probe-y.scope
```

Três conclusões provadas, não supostas:

1. Drop-ins **são aplicados a units transientes** (`Transient=yes` + `DropInPaths` preenchido).
2. A truncagem de prefixo por hífen funciona em **múltiplos níveis** e os drop-ins **empilham**.
3. `Slice=` num drop-in **redireciona** o scope transiente para outra slice — confirmado pelo `ControlGroup` real.

Como o scope do Flatpak se chama `app-flatpak-<app-id>-<pid>.scope` e **nenhum app-id instalado contém hífen**, o diretório `app-flatpak-<app-id>-.scope.d/` casa exatamente com aquele aplicativo, com precisão por app e sem tocar em mais nada.

---

## O que NÃO fazer (restrição de design, com justificativa técnica)

O usuário sugeriu "limpar a memória swap automaticamente". Isso é a solução errada e **não deve ser implementado**. Os quatro motivos:

1. **A zram já é RAM.** `zramctl` mostra `/dev/zram0` com zstd, DATA 5,3G comprimidos para 1,3G residentes. Não existe "sujeira" a limpar: é um bloco comprimido de páginas anônimas vivas, não cache descartável.
2. **`swapoff -a && swapon -a` causaria exatamente o freeze que se quer evitar.** Com 6,1 GiB paginados e 4,8 GiB disponíveis, o `swapoff` força a descompressão de tudo de volta para uma RAM que não comporta. O resultado determinístico é OOM imediato ou um thrashing muito pior que o original.
3. **`vm.swappiness=180` não é bug.** É a recomendação oficial para zram e o padrão do Pop!_OS 22.04 com zram, já documentado em `aurora/99-aurora.conf` linha 2 ("NAO reduzir"). Com zram, o custo de trazer uma página de volta é uma descompressão em RAM, não I/O de disco. Reduzir swappiness aqui piora a situação: mantém páginas frias ocupando RAM não comprimida.  <!-- noqa-acento -->
4. **Um cron de `drop_caches` ou de limpeza de swap trata sintoma e piora a latência.** Descartar o cache de página força releitura de disco de tudo que estava quente, aumentando o PSI de I/O — o mesmo `io some avg300=17,15` que já foi medido como rastro do incidente.

A causa é ausência de teto no consumidor. A sprint ataca o teto.

Também está **fora de escopo e proibido tocar**: qualquer coisa do tuning térmico do dossiê de 09/07 (`aurora-root-apply`, `aurora-thermal-apply.sh`, `aurora-switcher`, `aurora-watchdog-check.sh`, sentinela `/etc/aurora/allow-powersave`, perfil de fan `balanced-performance`). Está estável e não tem relação com este modo de falha.

---

## Escopo (touches autorizados)

Arquivos a modificar (5):

- `aurora/earlyoom.default` — F1
- `aurora/aurora-bootstrap.sh` — F2 (função nova + mapa declarativo)
- `aurora/units/browser.slice` — F2b (recalibração)
- `aurora/mem-snapshot` — F4
- `aurora/CHANGELOG.md` — entrada da versão

Arquivos a criar: **nenhum**. Toda a sprint reaproveita infraestrutura existente.

Arquivos NÃO a tocar (proibido):

- `aurora/99-aurora.conf` — `vm.swappiness`, `vm.page-cluster`, `vm.watermark_scale_factor`. Byte a byte inalterado.
- `aurora/aurora-root-apply`, `aurora/aurora-thermal-apply.sh`, `aurora/aurora-switcher`, `aurora/aurora-watchdog-check.sh`, `aurora/nbfc/` — tuning térmico.
- `aurora/amdgpu-dmcub-watchdog`, `aurora/aurora-gpu-revive`, `aurora/aurora-compositor-heartbeat.sh` — defesa do outro modo de falha.
- `aurora/oom-postmortem` — apenas verificar regressão, não editar (ver F4).
- `aurora/product-oom-watchdog` — só entra em cena em F3, que é contingência.
- `aurora/units/claude.slice`, `electron.slice`, `heavy-other.slice`, `luna.slice`, `steam.slice`, `ollama.slice` — ver "Achados colaterais".
- A função `aplica_slice_override()` existente e suas 10 chamadas — ver F2, motivo 2.
- `functions/`, `scripts/`, `.githooks/`, `hooks/`, `cca/`, `vault/`.

---

## Aritmética: por que 8G/10G nunca mordeu e quais valores mordem

**Fato que fecha a discussão:** o Edge disparou o freeze com **6,21 GiB** de RSS. O `MemoryHigh` vigente da `browser.slice` é **8G**. Ou seja, mesmo que o Edge estivesse dentro da slice, o teto atual **não teria evitado o freeze** — ele nunca teria sido alcançado. Aplicar F2 sem recalibrar entrega um limite que não morde.

Os valores 8G/10G foram dimensionados para uma máquina maior. Verificação da soma vigente contra a RAM real:

```
RAM física ................................ 14,81 GiB
browser.slice  MemoryMax = 10 GiB
claude.slice   MemoryMax = 12 GiB
steam.slice    MemoryMax = 11 GiB
ollama.slice   MemoryMax =  9 GiB
luna.slice     MemoryMax =  8 GiB
electron.slice MemoryMax =  6 GiB
heavy-other    MemoryMax =  6 GiB
                          -------
soma dos tetos ........................... 62 GiB para 14,81 GiB de RAM
```

Teto de cgroup é dispositivo de **contenção**, não alocador global — a soma não precisa caber. O critério correto é individual:

> Para cada slice: `MemoryMax da slice + reserva do sistema <= RAM física`, com folga para as demais slices.

Reserva do sistema medida: GNOME + Xorg + gnome-shell + daemons + terminal ocupam confortavelmente **3,0 GiB** (a máquina em repouso pós-kill marcava 8,7 GiB usados já incluindo Chrome com 1,05 GiB na `browser.slice`, `claude` e quatro Flatpaks).

Aplicando o critério à `browser.slice`:

```
VIGENTE:  10,0 (MemoryMax) + 3,0 (sistema) = 13,0 GiB
          sobra para agente + electron + heavy + luna: 14,81 - 13,0 = 1,81 GiB  -> NÃO FECHA

PROPOSTO:  6,0 (MemoryMax) + 3,0 (sistema) =  9,0 GiB
          sobra para agente + electron + heavy + luna: 14,81 -  9,0 = 5,81 GiB  -> FECHA
```

Valores propostos para `aurora/units/browser.slice`:

| Campo | Vigente | Proposto | Justificativa |
|---|---|---|---|
| `MemoryHigh` | 8G | **4G** | Ponto de estrangulamento suave. Precisa ficar **abaixo** dos 6,21 GiB medidos para morder. Acima de 4G o kernel faz reclaim direcionado **ao cgroup do navegador**, em vez do reclaim global que foi o que roubou as páginas do compositor. O navegador fica lento; a máquina, viva. |
| `MemoryMax` | 10G | **6G** | Teto duro abaixo do pico medido de 6,21 GiB: uma repetição exata do incidente fica contida por construção. 6G = 40,5 % da RAM; um navegador sozinho nunca é dono de metade da máquina. |
| `MemorySwapMax` | 4G | **3G** | Limita quanto do navegador pode ser empurrado para a zram. 3G descomprimidos custam aproximadamente 0,75 GiB de RAM real na razão medida de 4,1x. Amortece o estrangulamento sem devolver pressão ao sistema. |
| `CPUWeight` | 80 | 80 | Inalterado. |

Diferença entre `High` e `Max` (o executor precisa entender, senão calibra errado): `MemoryHigh` **estrangula e faz reclaim**, nunca mata. `MemoryMax` é o ponto onde o OOM killer do cgroup atua. Manter 2 GiB de distância entre os dois é deliberado: dá ao navegador uma faixa larga de degradação graciosa antes de qualquer morte.

Verificação aritmética da entrega: `4 < 6,21` (o `High` morde) e `6 < 6,21` (o `Max` contém). Ambas fecham.

---

## F1 — Quick-win no earlyoom

Risco praticamente zero, totalmente reversível, aplicar já.

### O que fazer

Estender o `--prefer` de `aurora/earlyoom.default` com os `comm` dos Flatpaks descartáveis. **Não** alterar `-r`, `-m`, `-M` nem o `--avoid`.

Termos a acrescentar (browsers, chat e música — estado recuperável):

```
msedge | waterfox | Discord | spotify | telegram-deskto | zapzap
```

Três armadilhas obrigatórias:

1. **`comm` tem no máximo 15 caracteres** (`TASK_COMM_LEN`). Por isso `telegram-desktop` aparece como `telegram-deskto`. Todo termo novo precisa ser conferido com o app aberto antes de virar regex ancorado.
2. **O regex é sensível a maiúsculas.** O `--prefer` atual já tem `discord` em minúscula, mas o `comm` do Flatpak do Discord é `Discord` — a entrada existente nunca casou. Acrescentar a forma correta, sem remover a antiga (invariante "zero funções removidas" por analogia: não retirar entrada que possa cobrir a versão nativa).
3. **`--prefer` é ancorado** (`^(...)$`). Não usar fragmentos.

Deliberadamente **fora** do `--prefer`: `gimp`, `krita`, `obs`, `onlyoffice`, `obsidian`, `thunderbird`. Todos carregam trabalho não salvo; priorizar a morte deles troca um freeze por perda de dados. Eles ganham teto via F2, que estrangula em vez de matar — que é a ferramenta certa para esse grupo.

### Os DOIS passos (armadilha registrada no dossiê)

O dossiê de 09/07 registra, na seção 5C, a armadilha "editar repo sem `bootstrap` não tem efeito". Confirmado nesta sessão: `aurora-bootstrap.sh:124` faz `copia_se_diff "$AURORA_REPO/earlyoom.default" /etc/default/earlyoom root:root 0644`, e `copia_se_diff` só copia quando `cmp -s` acusa diferença. Portanto:

```bash
# Passo 1 - editar a fonte de verdade versionada
$EDITOR ~/.config/zsh/aurora/earlyoom.default

# Passo 2 - reaplicar (sem isso, /etc/default/earlyoom continua o antigo)
sudo -v
~/.config/zsh/aurora/aurora-bootstrap.sh --post-update
sudo systemctl restart earlyoom.service
```

`earlyoom.service` só relê `EARLYOOM_ARGS` no start; `reload` não existe para essa unit.

### Proof-of-work de F1

```bash
# a) fonte e destino idênticos apos o bootstrap
cmp -s ~/.config/zsh/aurora/earlyoom.default /etc/default/earlyoom && echo "IDENTICOS"
# esperado: IDENTICOS

# b) o daemon vivo está usando os args novos
systemctl show earlyoom.service -p ExecStart | grep -o "msedge"
# esperado: msedge
ps -o args= -p "$(pgrep -x earlyoom)" | grep -c msedge
# esperado: 1

# c) unit saudável
systemctl is-active earlyoom.service   # esperado: active

# d) cada comm novo confere com o processo real (rodar com os apps abertos)
ps -eo comm | sort -u | grep -iE 'edge|waterfox|discord|spotify|telegram|zapzap'
# esperado: msedge, waterfox, Discord, spotify, telegram-deskto, zapzap
# QUALQUER divergencia -> corrigir o regex ANTES de fechar a fase

# e) sintaxe PT-BR
python3 ~/.config/zsh/scripts/validar-acentuacao.py --paths aurora/earlyoom.default
```

---

## F2 — Teto de memória para Flatpak via drop-in de scope

Mecanismo já provado em bancada nesta sessão (ver "Probe decisiva"). Aplicar já, **mas só declarar resolvido depois do teste com o Edge real**.

### Mudança de mecanismo em relação à hipótese inicial (e por quê)

A hipótese original era estender `aplica_slice_override()` para procurar o `.desktop` nos caminhos de export do Flatpak. **Isso não deve ser feito**, por dois motivos medidos:

**Motivo 1 — o `systemd-run --scope` é anulado pelo próprio Flatpak.** O binário do Flatpak 1.14.6 contém `StartTransientUnit`, `org.freedesktop.systemd1.Manager` e o template `app-flatpak-%s-%d.scope`. Ele cria o **seu próprio** scope transiente e move o processo para lá. Como não passa a propriedade `Slice`, o gerenciador de usuário aplica o padrão `app.slice`. Um `systemd-run --user --slice=browser.slice --scope` externo é descartado nesse momento. Evidência direta: `app-flatpak-com.rtosta.zapzap-15710.scope` mostra `Slice=app.slice` e `MemoryHigh=infinity` estando o Flatpak rodando, enquanto o Chrome nativo lançado pelo mesmo padrão de override mostra `Slice=browser.slice`.

**Motivo 2 — destruiria arquivos customizados do usuário.** `aplica_slice_override()` faz `sed ... "$src" > "$dst"`, isto é, **sobrescreve** o destino quando não encontra o marcador `Aurora 2.1 override`. E `~/.local/share/applications/com.microsoft.Edge.desktop` **já existe e é customizado**: `Version=1.1`, `GenericName=Navegador da Internet`, `Comment=Acessar a internet`, com `Actions=new-window;new-private-window;` traduzidas, enquanto o export do Flatpak traz `Version=1.0` e `GenericName=Web Browser`. Rodar a função sobre esse caminho apagaria a customização. O mesmo vale para os outros dez `.desktop` de Flatpak já presentes em `~/.local/share/applications/`.

A função `aplica_slice_override()` e suas 10 chamadas ficam **intactas**: elas funcionam para apps nativos, com prova (`run-re99...scope` dentro de `browser.slice`).

### O mecanismo correto

Criar drop-ins de scope por app-id em `~/.config/systemd/user/`, contendo apenas o redirecionamento de slice. Os números continuam morando nas units de slice — fonte única de verdade, sem duplicação.

Caminho: `~/.config/systemd/user/app-flatpak-<app-id>-.scope.d/50-aurora-slice.conf`

Conteúdo (exemplo do Edge):

```ini
# Aurora - teto de memória para Flatpak (drop-in por prefixo de scope transiente)
# O Flatpak cria app-flatpak-<app-id>-<pid>.scope sozinho e sem Slice=; este
# drop-in redireciona para a slice correta. Os limites vivem na slice, não aqui.
[Scope]
Slice=browser.slice
```

**Proibido usar o prefixo raso `app-.scope.d/`**: ele casaria também com `app-gnome-aurora\x2dcompositor\x2dhb-4180.scope`, `app-gnome-ulauncher-4213.scope` e `app-gnome-touchegg-4220.scope`, que são infraestrutura de sessão e o próprio mecanismo de recuperação do outro freeze. Somente diretórios por app-id completo.

**Pré-condição verificada**: nenhum dos 23 app-ids instalados contém hífen (`flatpak list --app --columns=application | grep -c -e '-'` retorna `0`). Se um app-id com hífen for instalado no futuro, o prefixo trunca no lugar errado e o drop-in casaria demais. O executor deve incluir essa checagem no código, com `warn` quando o app-id contiver hífen.

### Mapa declarativo app-id para slice

Implementar em `aurora/aurora-bootstrap.sh` uma função `aplica_dropin_flatpak()` no mesmo estilo de `aplica_slice_override()`, inserida logo após ela (por volta da linha 307, antes do bloco "4. Reload systemd e enable" na linha 308 — assim o `systemctl --user daemon-reload` que já existe cobre os drop-ins novos), seguida de 12 chamadas declarativas:

```
# browser.slice
aplica_dropin_flatpak "com.microsoft.Edge"                "browser.slice"
aplica_dropin_flatpak "net.waterfox.waterfox"             "browser.slice"

# electron.slice
aplica_dropin_flatpak "com.discordapp.Discord"            "electron.slice"
aplica_dropin_flatpak "md.obsidian.Obsidian"              "electron.slice"
aplica_dropin_flatpak "com.spotify.Client"                "electron.slice"
aplica_dropin_flatpak "org.telegram.desktop"              "electron.slice"

# heavy-other.slice
aplica_dropin_flatpak "com.obsproject.Studio"             "heavy-other.slice"
aplica_dropin_flatpak "org.gimp.GIMP"                     "heavy-other.slice"
aplica_dropin_flatpak "org.kde.krita"                     "heavy-other.slice"
aplica_dropin_flatpak "org.onlyoffice.desktopeditors"     "heavy-other.slice"
aplica_dropin_flatpak "io.gitlab.theevilskeleton.Upscaler" "heavy-other.slice"
aplica_dropin_flatpak "org.mozilla.thunderbird_esr"       "heavy-other.slice"
```

Requisitos da função:

1. **Idempotente**: se o arquivo existe com conteúdo idêntico, retorna sem escrever nem logar (mesmo contrato do `copia_se_diff` e do `copia_user` já usados no arquivo).
2. **Condicional à presença**: só cria o drop-in se o app estiver instalado (`flatpak info <app-id>` com saída silenciada, ou consulta a `flatpak list --app --columns=application`). Espelha o `[ -f "$src" ] || return 0` da função irmã.
3. **Guarda de hífen**: se `<app-id>` contiver `-`, emitir `warn` e retornar sem criar, explicando que a truncagem de prefixo seria ambígua.
4. **Sem sudo**: `~/.config/systemd/user/` é do usuário, como `copia_user`.
5. **Log no padrão da casa**: `log "Drop-in Flatpak aplicado: <dir> (slice=<slice>)"`.
6. Modo `0644` no arquivo, `mkdir -p` no diretório.

### F2b — Recalibração da browser.slice

Aplicar os valores da seção de aritmética a `aurora/units/browser.slice`: `MemoryHigh=4G`, `MemoryMax=6G`, `MemorySwapMax=3G`, `CPUWeight=80` inalterado. Atualizar a `Description` para refletir que agora cobre Flatpak também.

`aurora-bootstrap.sh:270` já faz `copia_user` de `browser.slice`; a reaplicação é automática. Slices já carregadas aceitam a mudança com `systemctl --user daemon-reload`, sem reiniciar a sessão.

### Proof-of-work de F2 (obrigatório, é a fase que precisa de validação empírica)

```bash
# 0. sintaxe e reaplicacao
bash -n ~/.config/zsh/aurora/aurora-bootstrap.sh          # exit 0
~/.config/zsh/aurora/aurora-bootstrap.sh --post-update
systemctl --user daemon-reload

# 1. drop-ins existem
ls -d ~/.config/systemd/user/app-flatpak-*-.scope.d | wc -l
# esperado: 12

# 2. limites novos vivos na slice
SL=/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/browser.slice
cat $SL/memory.high $SL/memory.max $SL/memory.swap.max
# esperado: 4294967296 / 6442450944 / 3221225472

# 3. TESTE REAL - fechar o Edge, reabrir PELO LANCADOR do GNOME, e entao:
PID=$(pgrep -f 'extra/msedge --enable-features' | head -1); echo "PID=$PID"
cat /proc/$PID/cgroup
# esperado (a linha DEVE conter browser.slice):
# 0::/user.slice/user-1000.slice/user@1000.service/browser.slice/app-flatpak-com.microsoft.Edge-<N>.scope

# 4. o teto efetivo do cgroup do processo
CG=/sys/fs/cgroup$(cut -d: -f3 /proc/$PID/cgroup)
cat "$CG/memory.max"          # esperado: max  (ver nota abaixo)
cat "$(dirname "$CG")/memory.max"
# esperado: 6442450944  <- este e o teto que vale

# 5. confirmacao pelo systemd
SCOPE=$(systemctl --user list-units --type=scope --no-legend | grep -o 'app-flatpak-com.microsoft.Edge-[0-9]*\.scope' | head -1)
systemctl --user show "$SCOPE" -p Slice -p DropInPaths -p ControlGroup
# esperado: Slice=browser.slice
#           DropInPaths=/home/andrefarias/.config/systemd/user/app-flatpak-com.microsoft.Edge-.scope.d/50-aurora-slice.conf
#           ControlGroup=/user.slice/.../browser.slice/app-flatpak-com.microsoft.Edge-<N>.scope

# 6. o limite realmente morde (com o Edge com varias abas abertas)
cat $SL/memory.events
# esperado apos uso pesado: campo "high" com contagem > 0 e "oom" = 0
#   -> reclaim direcionado aconteceu e ninguem foi morto: exatamente o objetivo

# 7. acentuacao
python3 ~/.config/zsh/scripts/validar-acentuacao.py --paths aurora/aurora-bootstrap.sh aurora/units/browser.slice
```

**Nota sobre o passo 4**: `memory.max` no scope em si permanece `max` **por projeto**, porque os limites vivem na slice pai. No cgroup v2 o teto efetivo é o mínimo ao longo de toda a cadeia de ancestrais; ver o `max` no scope e `6442450944` no pai é o resultado **correto**, não uma falha. Se o executor preferir um número visível no próprio scope, pode acrescentar `MemoryHigh=` ao drop-in, mas isso duplica a fonte de verdade e é desaconselhado.

**Critério de falha de F2**: se o passo 3 mostrar `app.slice` no caminho do cgroup, o mecanismo escapou — só então F3 entra em cena.

---

## F3 — Contingência (só se F2 falhar no teste do passo 3)

**Não aplicar preventivamente.** Esta fase existe para não deixar a sprint sem saída se uma versão futura do Flatpak passar `Slice=` explicitamente no `StartTransientUnit`, o que sobrescreveria o drop-in.

### Veredito: opção (b), estender o `product-oom-watchdog`

Avaliação das três alternativas contra a evidência medida:

**(a) Drop-in em `~/.config/systemd/user/app.slice.d/` limitando toda a app.slice — REJEITADA.**
Medição de quem mora em `app.slice` hoje: `app-gnome-aurora\x2dcompositor\x2dhb-4180.scope` (o heartbeat do compositor, que é justamente o mecanismo de recuperação do freeze de 09/07), `app-gnome-ulauncher-4213.scope`, `app-gnome-touchegg-4220.scope`, `app-org.gnome.Terminal.slice`, `app-gnome-hidpi\x2ddaemon`, `app-gnome-dracula\x2dvideo\x2dwallpaper` e doze slices `app-dbus-*` de serviços do GNOME. Um teto agregado ali estrangula o compositor, o lançador e o terminal junto com o navegador — trata um freeze provocando outro, e desarma a defesa do modo de falha que já estava coberto. Além disso, um limite agregado não isola: um único app comilão consome a cota de todos os outros.

**(c) Wrapper de `flatpak run` no padrão do `google-chrome-wrapper.sh` — REJEITADA.**
Não ataca a causa. O escape acontece **dentro** do Flatpak, depois do `exec`: as strings `StartTransientUnit` e `app-flatpak-%s-%d.scope` estão no binário 1.14.6. Um wrapper externo sofre exatamente o mesmo destino que o `systemd-run --scope`. Seria trabalho novo com falha idêntica e comprovada.

**(b) Estender o `product-oom-watchdog` — ESCOLHIDA.**
Justificativa: já roda (`systemctl is-active product-oom-watchdog.service` retorna `active`), já é root, já tem `ReadWritePaths=/sys/fs/cgroup`, já varre cgroups num laço de 2 s, e hoje é **cego a Flatpak** — `SLICES_MONITORED` (`product-oom-watchdog:28-40`) lista só as slices, e nenhum Flatpak entra nelas. Estender resolve duas coisas de uma vez: passa a enxergar os Flatpaks e passa a poder limitá-los. É a única opção cirúrgica: age no scope específico, sem tocar em `app.slice`, sem wrapper, sem `.desktop`.

Esboço da extensão, caso seja necessária:

1. A cada N ciclos (N tal que o custo fique perto de 10 s, não 2 s), listar `/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/app.slice/app-flatpak-*.scope`.
2. Para cada scope cujo `memory.max` seja `max`, resolver o app-id a partir do nome do diretório e consultar o mesmo mapa app-id para slice de F2.
3. Aplicar `systemctl --user --machine=andrefarias@.host set-property <scope> MemoryHigh=<n> MemoryMax=<n>`.
4. Acrescentar os scopes reconhecidos ao cálculo de culpa que hoje só considera `SLICES_MONITORED`.

**Detalhe que precisa de validação empírica se F3 for acionada**: o watchdog roda como root e `systemctl --user` exige barramento de usuário. A forma correta é `--machine=<usuario>@.host` ou exportar `XDG_RUNTIME_DIR=/run/user/1000` mais `DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus`. Validar com um scope de teste antes de escrever a lógica definitiva.

---

## F4 — Alerta preventivo por PSI

Segura, aplicar já.

Hoje o usuário só descobre o problema quando a tela já travou. Nenhuma infraestrutura nova: o alerta vai dentro do `aurora/mem-snapshot`, que já roda a cada 30 s via `mem-snapshot.timer` e já lê `/proc/pressure/memory` (linhas 39-54).

### Por que no mem-snapshot e não no aurora-health-check

`aurora-health.timer` dispara a cada 30 min (`OnUnitActiveSec=30min`). O evento que se quer capturar se desenvolve na escala de dezenas de segundos. Uma cadência de 30 min alerta depois do freeze, o que é inútil. `mem-snapshot.timer` roda a cada 30 s (`OnUnitActiveSec=30s`) — cadência certa. Além disso o `mem-snapshot` já calcula o `top15` por RSS, então o alerta pode **nomear o culpado** sem trabalho extra.

### Por que PSI e não `free`

Três razões, todas com evidência:

1. O dossiê de 09/07 já registra o falso-positivo: o `oom-postmortem` acusou "S2 pressão de memória" para um freeze que **não** foi de memória, e a correção documentada em `oom-postmortem:62-72` foi justamente estreitar a janela. Gatilho baseado em ocupação é ambíguo por natureza.
2. PSI discrimina os dois modos de falha com precisão cirúrgica. No freeze de 09/07, no minuto exato, havia `mem_avail` de aproximadamente 5,5 GB (36 %) e **PSI avg10 = 0.00** — um gatilho por PSI teria ficado corretamente calado. No incidente de hoje o PSI de memória estava alto. Um gatilho por `free` teria disparado nos dois casos ou em nenhum.
3. PSI mede o que o usuário sente: fração do tempo de parede em que houve travamento por espera de memória. `free` mede ocupação, e ocupação alta com zram é o estado **normal** desta máquina.

### Limiar proposto, ancorado na baseline medida

Baseline saudável medida hoje, com o thrashing já cessado:

```
/proc/pressure/memory:  some avg10=0.00 avg60=0.00 avg300=0.00 a 0.02
                        full avg10=0.00 avg60=0.00 avg300=0.00 a 0.02
```

| Nível | Condição | Justificativa |
|---|---|---|
| **AVISO** | `memory some avg10 >= 10.00` em **2 amostras consecutivas** (60 s) | 10.00 é aproximadamente 500x o pico da baseline (0.02) — falso-positivo é praticamente impossível. Ao mesmo tempo, 10 % do tempo de parede com **alguma** tarefa travada já é lentidão perceptível, e ainda está muito antes do congelamento. A exigência de 2 amostras filtra pico transiente (mesma disciplina do `consecutive_critical < 2` já usada em `product-oom-watchdog:174-177`). |
| **CRÍTICO** | `memory full avg10 >= 10.00` em **1 amostra** | `full` significa **todas** as tarefas estagnadas — é literalmente a tela travada. Por definição `full <= some`, então um `full` de 10 é muito mais severo que um `some` de 10 e não merece esperar confirmação. Com baseline de 0.00, qualquer valor sustentado aqui é anomalia real. |

O PSI de I/O **não** serve de gatilho preventivo: a leitura relevante medida foi `io some avg300=17.15`, uma janela de 300 s que só acusa depois do estrago e que confunde I/O de disco legítimo (`apt`, build, cópia de arquivo) com thrashing. Fica registrado como sinal de confirmação em post-mortem, não como gatilho.

### Requisitos de implementação de F4

1. Ler também a linha `full` de `/proc/pressure/memory` (o bloco `awk` das linhas 44-54 hoje casa só `/^some/`).
2. Estado entre execuções em `/run/mem-snapshot.psi-state` (formato `chave=valor`, lido com `grep`/`cut`, **sem** `source`), contendo o contador de amostras consecutivas acima do limiar e o epoch do último alerta. `/run` é tmpfs: o contador zera no boot, que é o comportamento correto.
3. **Cooldown de 300 s** entre notificações. Sem isso, um episódio de 10 min gera 20 notificações.
4. Entrega da notificação a partir de um processo **root**, que é o caso do `mem-snapshot`: `runuser -u andrefarias -- env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus notify-send ...`, sempre com `|| true` para não derrubar a coleta se a sessão gráfica não existir. O padrão `runuser -u "$USUARIO"` já é usado em `aurora-health-check:11` e `oom-postmortem:21`.
5. Registrar também com `logger -t aurora-mem-alert`, para o alerta aparecer no journal e ficar disponível ao post-mortem.
6. Mensagem deve **nomear o culpado**, reaproveitando o `top15` já calculado. Exemplo: `Pressão de memória em 12% — msedge está com 6198 MiB. Feche abas ou o aplicativo.`
7. Nunca abortar a coleta: se qualquer passo do alerta falhar, a linha CSV ainda tem que ser escrita. O `flock -n 9 || exit 0` da linha 18 e o `set -u` da linha 12 permanecem.

**Restrição dura — não alterar o esquema do CSV.** `oom-postmortem:72` lê a coluna de PSI por **índice** (`($6+0) > 5`). Inserir coluna quebra o post-mortem silenciosamente. Acrescentar coluna depois de `top15` também é ruim: o cabeçalho só é escrito quando o arquivo está vazio (`mem-snapshot:21`), e o log atual tem 4367 linhas, então ficaria um cabeçalho de 8 colunas descrevendo linhas de 10. Decisão: o valor de `full` é lido **em memória**, usado para o alerta e **descartado**. Persistir `psi_full` no CSV vira sprint própria, registrada abaixo como não-objetivo com o motivo.

### Proof-of-work de F4

```bash
# a) sintaxe e acentuacao
bash -n ~/.config/zsh/aurora/mem-snapshot                 # exit 0
python3 ~/.config/zsh/scripts/validar-acentuacao.py --paths aurora/mem-snapshot

# b) execucao real como root, sem quebrar a coleta
sudo systemctl start mem-snapshot.service
tail -1 /var/log/mem-snapshot.log
# esperado: linha nova com EXATAMENTE 8 campos
awk -F, 'END{print NF}' /var/log/mem-snapshot.log     # esperado: 8

# c) REGRESSAO do oom-postmortem: a coluna 6 continua sendo psi_some_avg10
tail -1 /var/log/mem-snapshot.log | awk -F, '{print "col6="$6}'
# esperado: col6=0.00 (numero, nao texto)
bash -n ~/.config/zsh/aurora/oom-postmortem   # arquivo NAO editado, so conferido
sha256sum ~/.config/zsh/aurora/oom-postmortem
# esperado: identico ao de antes da sprint (declarado como intocado)

# d) o alerta dispara com limiar forcado (sem precisar travar a maquina)
sudo env AURORA_PSI_AVISO=0.00 AURORA_PSI_CRITICO=0.00 /usr/local/sbin/mem-snapshot
journalctl -t aurora-mem-alert -n 5 --no-pager
# esperado: linha de alerta nomeando o processo de maior RSS
# e a notificacao visivel na area de trabalho

# e) cooldown funciona (2a execucao imediata NAO notifica de novo)
sudo env AURORA_PSI_AVISO=0.00 /usr/local/sbin/mem-snapshot
journalctl -t aurora-mem-alert -n 5 --no-pager | wc -l   # nao deve crescer

# f) baseline nao gera falso-positivo
cat /proc/pressure/memory
sudo systemctl start mem-snapshot.service
journalctl -t aurora-mem-alert --since "1 min ago" --no-pager | wc -l   # esperado: 0
```

Os limiares devem ser configuráveis por variável de ambiente com padrão embutido (mesmo contrato do `product-oom-watchdog:41-45`), justamente para que o teste (d) seja possível sem esgotar a memória da máquina.

---

## Ordem de aplicação e nível de segurança

| Fase | Aplicar já? | Observação |
|---|---|---|
| **F1** earlyoom | **Sim, segura.** | Risco praticamente zero. Reversível com `git revert` + `--post-update` + `restart`. Só exige conferir os `comm` com os apps abertos. |
| **F2** drop-ins Flatpak | **Sim**, mecanismo já provado em bancada — **mas só declarar resolvida após o passo 3 do proof-of-work com o Edge real.** | O escape do scope transiente é o risco técnico da sprint. A probe desta sessão provou que o drop-in vence; falta confirmar com o Flatpak de verdade. |
| **F2b** recalibrar browser.slice | **Sim, segura**, mas muda comportamento perceptível. | Com `MemoryHigh=4G` o navegador **vai** ficar lento com muitas abas, em vez de travar a máquina — isso é a entrega, não um defeito. Monitorar `memory.events` por 48 h: campo `high` crescendo é o esperado; campo `oom` diferente de zero significa que `MemoryMax=6G` está apertado demais e deve subir para 7G. |
| **F3** contingência | **Não aplicar.** | Só se o passo 3 de F2 mostrar `app.slice`. |
| **F4** alerta PSI | **Sim, segura.** | Só acrescenta leitura e notificação; a coleta CSV fica byte-compatível. |

---

## Acceptance criteria

1. `cmp -s aurora/earlyoom.default /etc/default/earlyoom` retorna 0 e `ps -o args= -p $(pgrep -x earlyoom)` contém `msedge`.
2. Cada `comm` acrescentado ao `--prefer` foi confirmado com `ps -eo comm` com o aplicativo em execução; nenhum termo excede 15 caracteres.
3. `ls -d ~/.config/systemd/user/app-flatpak-*-.scope.d | wc -l` retorna 12.
4. Reabrindo o Edge pelo lançador do GNOME, `cat /proc/<pid>/cgroup` contém `browser.slice` e **não** contém `app.slice`.
5. `browser.slice` viva reporta `memory.high=4294967296`, `memory.max=6442450944`, `memory.swap.max=3221225472`.
6. `systemctl --user show <scope-do-edge> -p DropInPaths` aponta para o drop-in do Aurora.
7. `aplica_slice_override()` e suas 10 chamadas estão inalteradas; Chrome nativo continua com `Slice=browser.slice`.
8. Nenhum `.desktop` em `~/.local/share/applications/` foi criado ou modificado pela sprint (`git status` do home não se aplica; verificar por `find ~/.local/share/applications -newermt '<inicio da sprint>'` vazio).
9. `mem-snapshot` alerta quando o limiar é forçado a 0.00 e fica calado na baseline real; o log continua com exatamente 8 colunas e `$6` continua sendo `psi_some_avg10`.
10. Notificação chega à área de trabalho a partir do processo root e nomeia o processo de maior RSS.
11. `sha256sum` de `aurora/99-aurora.conf`, `aurora/oom-postmortem`, `aurora/product-oom-watchdog`, `aurora/aurora-root-apply` e `aurora/aurora-thermal-apply.sh` inalterados.
12. `bash -n` limpo nos três arquivos de shell tocados; `validar-acentuacao.py` exit 0 em todos os arquivos PT-BR tocados.
13. `zsh -ic 'true'` abre sem erro e `source ~/.config/zsh/.zsh_secrets && echo "${GIT_TOKEN_PESSOAL:0:4}"` imprime `ghp_`.
14. `aurora-bootstrap.sh --post-update` roda duas vezes seguidas e a segunda execução não emite nenhuma linha `Drop-in Flatpak aplicado` (idempotência provada).

---

## Invariantes a preservar (do BRIEF)

- **Acentuação PT-BR estrita** (BRIEF invariante 9, categoria PONTO-CEGO). Rodar `scripts/validar-acentuacao.py --paths` em todo arquivo tocado. Lembrar da ressalva permanente: exit 0 não garante 100 %, auditoria humana continua necessária.
- **Zero funções removidas** (BRIEF invariante 8). `aplica_slice_override()` não pode ser removida nem ter sua assinatura alterada. As entradas antigas do `--prefer` do earlyoom não podem ser retiradas, mesmo a `discord` minúscula que provavelmente nunca casou.
- **Autosync ativo** (BRIEF invariante 3). Rodar `git log --oneline -5` antes de qualquer commit manual — o autosync pode já ter capturado tudo. Não fazer `git push` manual.
- **Pre-commit aplica e informa; pre-push é a rede final** (BRIEF invariantes 5 e 6). Commit em PT-BR, imperativo, minúsculas, sem coautoria, sem menção a ferramenta de IA, sem emoji. Nada de `--no-verify` nem `SKIP_HOOKS`.
- **Runtime real obrigatório** (BRIEF tabela de proof-of-work): `bash -n` para `*.sh`, e para Aurora especificamente `bash -n` mais smoke com `aurora-health-check` ou `--post-update`.
- **Editar repo sem bootstrap não tem efeito** (dossiê 09/07, seção 5C). Vale para `earlyoom.default`, `browser.slice` e qualquer coisa que o `copia_se_diff`/`copia_user` distribua. Sempre os dois passos.
- **Nenhum débito** (BRIEF check 6 e 9). Achado colateral vira sprint nova, nunca `TODO` no código.

---

## Riscos e não-objetivos

**Riscos**

1. **O Flatpak pode passar a definir `Slice=` numa versão futura**, anulando o drop-in. Mitigação: F3 documentada com veredito. Detecção: o passo 6 do proof-of-work de F2 (`memory.events` com campo `high` crescendo) deixa de evoluir.
2. **`MemoryHigh=4G` pode ser apertado demais para o uso real do usuário.** Mitigação: janela de observação de 48 h em `memory.events`; se `oom` for diferente de zero, subir `MemoryMax` para 7G. `High` estrangula, não mata, então o pior caso é lentidão, não perda.
3. **`electron.slice` e `heavy-other.slice` têm teto agregado de 6G.** Ao trazer quatro apps Electron (Discord, Obsidian, Spotify, Telegram) para a mesma slice, o teto passa a ser compartilhado. Com `MemoryHigh=4G` e `MemoryMax=6G`, o cenário ruim é o OOM do cgroup matar o conjunto. Mitigação nesta sprint: **não** alterar esses valores agora; medir `memory.peak` das duas slices por 48 h e só então decidir. Está explicitamente registrado como condição de disparo de sprint nova, não como `TODO`.
4. **Um app-id com hífen instalado no futuro** quebraria a truncagem de prefixo. Mitigação: guarda com `warn` dentro da função (requisito 3 de F2).
5. **Aplicativos já em execução não migram** para a nova slice — o drop-in age no momento do lançamento. Depois da sprint, o Edge precisa ser fechado e reaberto. Isso deve constar da mensagem de conclusão para o usuário.

**Não-objetivos (fora desta sprint, por decisão explícita)**

- Qualquer forma de limpeza de swap, `swapoff`, `drop_caches` ou mudança em `vm.swappiness`. Justificado em detalhe na seção "O que NÃO fazer".
- Tuning térmico do dossiê de 09/07 em qualquer aspecto.
- Recalibrar `claude.slice`, `steam.slice`, `luna.slice`, `ollama.slice`, `electron.slice`, `heavy-other.slice` (ver achados colaterais).
- Persistir `psi_full` no CSV do `mem-snapshot` (quebra de esquema e de cabeçalho; motivo detalhado em F4).
- Corrigir o `--avoid` do earlyoom (ver achados colaterais).
- Trazer PWAs do Chrome (`chrome-*-Default.desktop`) para dentro de slice.

---

## Achados colaterais (registrados, NÃO corrigir nesta sprint)

Todos descobertos durante a exploração desta sessão, com evidência. Cada um é candidato a sprint própria, conforme o protocolo antidébito (BRIEF check 5, forma C).

1. **`claude.slice` está superdimensionada para esta máquina.** `MemoryHigh=10G / MemoryMax=12G` numa RAM de 14,81 GiB significa que o teto só é alcançado quando a máquina já morreu. Mexer nisso arrisca as sessões do `cca`, então fica para sprint dedicada com medição de `memory.peak` antes.
2. **Comentário do bootstrap diverge das units.** `aurora-bootstrap.sh:273` diz "Aurora 2.2 - slices Luna / Steam / heavy-other (todas com `OOMPolicy=kill`)", mas nenhuma das três units contém a diretiva `OOMPolicy`. Ou o comentário mente ou a diretiva foi perdida.
3. **Regras provavelmente mortas no `--avoid` do earlyoom.** O earlyoom v1.6.2 casa contra o nome do processo, limitado a 15 caracteres. As entradas `python.*main\.py`, `python.*luna` e `venv_tts.*python` não têm como casar um `comm` de 15 caracteres — a proteção da Luna pode estar inoperante. Exige verificação com `earlyoom -d` e a Luna rodando.
4. **`discord` em minúscula no `--prefer` nunca casou o Flatpak**, cujo `comm` é `Discord`. F1 acrescenta a forma correta sem remover a antiga, mas a antiga continua sendo código morto se não houver Discord nativo.
5. **`notify-send` chamado como root no `product-oom-watchdog`.** A função `notify()` (`product-oom-watchdog:112-121`) executa `notify-send` diretamente e a unit roda como root, sem `DBUS_SESSION_BUS_ADDRESS`. Só captura `FileNotFoundError`, então uma falha de barramento é silenciosa. Provável: o watchdog mata slices sem nunca avisar o usuário. Precisa de verificação e, se confirmado, do mesmo padrão `runuser` que F4 usa.
6. **PWAs do Chrome escapam da `browser.slice`.** `app-com.google.Chrome-5820.scope` está em `app.slice` com `MemoryHigh=infinity`, lançado a partir de `~/.local/share/applications/chrome-gjcmcplpgihbecacndmmbaenpfgimlec-Default.desktop`. A técnica de drop-in de F2 resolveria, mas o nome do scope embute o ID da extensão e exigiria mapa próprio.
7. **`aurora-health-check` está cego a memória.** Verifica SMART, disco, térmica de CPU, GPU, iGPU e chassi — nada de memória. F4 cobre o alerta em tempo real; um resumo de 30 min no health-check seria complementar.

---

## Plano de implementação

### Tarefa 0 — Verificar a hipótese antes de escrever qualquer linha

```bash
cd ~/.config/zsh
grep -n "aplica_slice_override" aurora/aurora-bootstrap.sh          # esperado: 280, 297-306
grep -n "earlyoom.default" aurora/aurora-bootstrap.sh               # esperado: 124
grep -n "browser.slice" aurora/aurora-bootstrap.sh                  # esperado: 270
grep -n "psi_avg10\|/proc/pressure/memory" aurora/mem-snapshot      # esperado: 41-53
grep -n '(\$6+0) > 5' aurora/oom-postmortem                         # esperado: 72
systemctl is-active earlyoom.service mem-snapshot.timer             # esperado: active active
```

Qualquer divergência para o que este spec afirma: **parar** e reportar antes de prosseguir.

### Tarefa 1 — F1, earlyoom

1. Editar `aurora/earlyoom.default`: acrescentar ao `--prefer` os termos `msedge`, `waterfox`, `Discord`, `spotify`, `telegram-deskto`, `zapzap`. Manter tudo o mais idêntico.
2. Atualizar o comentário do cabeçalho citando que a lista cobre também Flatpak e explicando o limite de 15 caracteres do `comm`.
3. `sudo -v && ./aurora/aurora-bootstrap.sh --post-update && sudo systemctl restart earlyoom.service`.
4. Proof-of-work de F1, itens (a) a (e).

### Tarefa 2 — F2b, recalibrar browser.slice

1. Editar `aurora/units/browser.slice`: `MemoryHigh=4G`, `MemoryMax=6G`, `MemorySwapMax=3G`. Atualizar a `Description` para mencionar Flatpak.
2. `./aurora/aurora-bootstrap.sh --post-update && systemctl --user daemon-reload`.
3. Conferir os três valores no cgroup vivo (passo 2 do proof-of-work de F2).

### Tarefa 3 — F2, função e mapa no bootstrap

1. Escrever `aplica_dropin_flatpak()` logo após `aplica_slice_override()` (por volta da linha 295), atendendo aos seis requisitos da seção F2.
2. Acrescentar as 12 chamadas declarativas, agrupadas por slice e com comentário de grupo, antes do bloco "4. Reload systemd e enable".
3. `bash -n aurora/aurora-bootstrap.sh`.
4. `./aurora/aurora-bootstrap.sh --post-update`, depois rodar de novo para provar idempotência.
5. Proof-of-work de F2, passos 0 a 7. **O passo 3 exige fechar e reabrir o Edge pelo lançador do GNOME.**
6. Se o passo 3 falhar, **parar** e abrir F3 conforme o veredito, sem improvisar.

### Tarefa 4 — F4, alerta PSI no mem-snapshot

1. Estender o bloco `awk` para extrair também a linha `full`.
2. Acrescentar leitura e escrita do estado em `/run/mem-snapshot.psi-state`.
3. Acrescentar a avaliação de limiar (aviso com 2 amostras, crítico com 1) e o cooldown de 300 s.
4. Acrescentar a notificação via `runuser` mais `logger`, com `|| true` em tudo.
5. Limiares configuráveis por ambiente com padrão embutido.
6. **Não** alterar a linha `printf` final nem o cabeçalho CSV.
7. `bash -n` e proof-of-work de F4, itens (a) a (f).

### Tarefa 5 — CHANGELOG e fechamento

1. Entrada em `aurora/CHANGELOG.md` descrevendo as quatro fases e a mudança de tetos.
2. `python3 scripts/validar-acentuacao.py --paths aurora/earlyoom.default aurora/aurora-bootstrap.sh aurora/units/browser.slice aurora/mem-snapshot aurora/CHANGELOG.md docs/sprints/SPR-2026-08-07-freeze-pressao-memoria.md`
3. `sha256sum` dos arquivos declarados intocados, comparando com os valores de antes.
4. Smoke geral: `zsh -ic 'true'`, vault, `git log --oneline -3`.
5. `git log --oneline -5` para checar se o autosync já capturou. Commit manual só se necessário.
6. Avisar o usuário que o Edge precisa ser fechado e reaberto para entrar na slice.

---

## Mensagem de commit sugerida

```
feat: conter Flatpak em slice de memória e alertar por PSI antes do thrashing

Freeze de 2026-08-07 foi thrashing de paginação, não hang de display: Edge
Flatpak com 6,21 GiB de RSS sem nenhum teto, em 14,81 GiB de RAM.

Duas falhas corrigidas:
- aplica_slice_override so cobria apps nativos; os 23 Flatpaks da maquina
  rodavam sem MemoryHigh/MemoryMax. O Flatpak cria o proprio scope transiente
  em app.slice, entao systemd-run --scope nao resolve. Solucao: drop-in por
  prefixo de scope (app-flatpak-<id>-.scope.d) redirecionando para a slice.
- earlyoom --prefer nao continha msedge, o maior consumidor da maquina.

browser.slice recalibrada de 8G/10G/4G para 4G/6G/3G: o teto antigo estava
acima do pico medido e nunca teria mordido.

mem-snapshot passa a alertar por PSI (some avg10 >= 10 em 2 amostras;
full avg10 >= 10 em 1), reaproveitando o timer de 30s que ja existia.
```

---

## Referências

- BRIEF: `/home/andrefarias/.config/zsh/VALIDATOR_BRIEF.md`
- Dossiê do outro modo de falha: `/home/andrefarias/.config/zsh/aurora/DOSSIE-2026-07-09-termico-e-freeze.md` (seções 4, 5B e 5C)
- Precedente de formato: `docs/sprints/SPR-2026-07-03-cca-preflight.md`
- `aurora/aurora-bootstrap.sh:96-111` (`copia_se_diff`), `:124` (earlyoom), `:259-276` (`copia_user` e slices), `:280-306` (`aplica_slice_override` e chamadas)
- `aurora/product-oom-watchdog:28-45` (slices monitoradas e configuração), `:112-121` (`notify`), `:174-177` (dois ciclos consecutivos)
- `aurora/mem-snapshot:39-54` (leitura de PSI), `:66-68` (escrita CSV)
- `aurora/oom-postmortem:58-85` (S2, leitura da coluna 6)
- `aurora/99-aurora.conf:2` ("vm.swappiness=180 ... NAO reduzir")
