# Blindagem das máquinas

Sprints para fechar a infraestrutura pessoal: dois computadores compartilhados
entre duas pessoas, com celulares conectados neles.

Cada sprint traz **como verificar** e **como corrigir**. Nada aqui descreve o
estado atual das máquinas — quem lê precisa rodar a verificação para saber.
Isso é de propósito: o documento pode ser lido por qualquer um sem entregar
nada.

Ordem sugerida: 1, 2, 5, 3, 4. A primeira é a única que precisa vir primeiro.

---

## Sprint 1 — Saber o que está aberto

**Uma hora. Nada é alterado.**

Não dá para decidir o que proteger sem saber o que está exposto. Esta sprint só
mede, nas duas máquinas.

### Verificar

```bash
# o disco está cifrado?
lsblk -o NAME,FSTYPE,MOUNTPOINT | grep -i crypt
cat /etc/crypttab

# quem pode virar root, e sem senha?
sudo grep -rn "NOPASSWD" /etc/sudoers /etc/sudoers.d/

# chaves SSH sem frase secreta (a saída vazia é o que se quer)
for k in ~/.ssh/id_*; do
  case "$k" in *.pub) continue;; esac
  ssh-keygen -y -P "" -f "$k" >/dev/null 2>&1 && echo "SEM FRASE: $k"
done

# o que escuta a rede
ss -tulpn | grep LISTEN

# o que sobe junto com a sessão
systemctl --user list-unit-files --state=enabled

# quanto os aplicativos em caixa de areia realmente podem
cat ~/.local/share/flatpak/overrides/global 2>/dev/null
flatpak list --app --columns=application | while read -r a; do
  echo "== $a"; flatpak info --show-permissions "$a" 2>/dev/null | grep -E "filesystems|sockets|devices"
done
```

### Entregar

Um arquivo por máquina, **fora de qualquer repositório**, com o resultado. Ele
é um mapa das suas fraquezas: trate como senha.

```bash
mkdir -p ~/.local/state/blindagem
{ ...comandos acima... } > ~/.local/state/blindagem/$(hostname)-$(date +%F).txt
chmod 600 ~/.local/state/blindagem/*
```

---

## Sprint 2 — Cifrar o que dói

**Duas a quatro horas, por máquina.**

Se o disco não estiver cifrado, quem levar o computador lê tudo: documentos,
email baixado, chaves, fotos, gravações.

### Caminho A — o certo, e o mais trabalhoso

Reinstalar o sistema com criptografia de disco ligada no instalador. O Pop!_OS
oferece na instalação. Exige backup completo antes e restaurar depois.

Vale quando a máquina já vai ser reinstalada por outro motivo.

### Caminho B — o que dá para fazer hoje

Um contêiner cifrado em arquivo, montado onde ficam os dados sensíveis. Não
exige reinstalar nada nem mexer nas partições.

```bash
sudo apt install cryptsetup

# 1. criar o arquivo (ajuste o tamanho)
fallocate -l 40G ~/cofre.img
chmod 600 ~/cofre.img

# 2. transformar em volume cifrado — pede a senha
sudo cryptsetup luksFormat ~/cofre.img

# 3. abrir, formatar, montar
sudo cryptsetup open ~/cofre.img cofre
sudo mkfs.ext4 /dev/mapper/cofre
mkdir -p ~/Cofre
sudo mount /dev/mapper/cofre ~/Cofre
sudo chown "$USER:$USER" ~/Cofre

# fechar quando terminar
sudo umount ~/Cofre && sudo cryptsetup close cofre
```

Duas funções no zsh para não decorar:

```bash
cofre-abrir()  { sudo cryptsetup open ~/cofre.img cofre &&
                 sudo mount /dev/mapper/cofre ~/Cofre &&
                 sudo chown "$USER:$USER" ~/Cofre && echo "cofre aberto em ~/Cofre"; }
cofre-fechar() { sudo umount ~/Cofre && sudo cryptsetup close cofre && echo "cofre fechado"; }
```

### O que vai para dentro

Gravações de reunião, documentos de trabalho, fotos pessoais, qualquer backup
de celular. **Mover, não copiar** — original em claro no disco anula o esforço.

### Cuidado

Esquecer a senha é perder o conteúdo. Guarde o cabeçalho LUKS em outro lugar,
que permite recuperar se o arquivo corromper:

```bash
sudo cryptsetup luksHeaderBackup ~/cofre.img --header-backup-file ~/cofre-header.bin
# guarde esse arquivo FORA da máquina, e trate como senha
```

---

## Sprint 3 — Fechar a caixa de areia

**Uma hora, por máquina.**

Aplicativos em Flatpak são isolados por padrão. Uma configuração global pode
desfazer isso para todos de uma vez, e isso costuma ser feito uma vez para
resolver um aplicativo específico e nunca mais revisto.

O que mais importa: `ssh-auth` dá ao aplicativo acesso ao seu agente SSH — ou
seja, às suas chaves. E `filesystems=home` anula o isolamento inteiro.

### Verificar

```bash
cat ~/.local/share/flatpak/overrides/global 2>/dev/null
```

### Corrigir

O Flatseal já está instalado e é a ferramenta certa. A regra: **permissão
excepcional vai no aplicativo que precisa, nunca no global.**

```bash
# ver o que cada um realmente tem, antes de mexer
flatpak info --show-permissions <aplicativo>

# remover uma permissão perigosa do global
flatpak override --user --nosocket=ssh-auth
flatpak override --user --nofilesystem=home

# e devolver só a quem precisa, um a um
flatpak override --user --filesystem=~/Documentos com.exemplo.App
```

Depois de mexer, abra cada aplicativo que você usa e confirme que ainda
funciona. Alguns vão pedir permissão de novo pelo diálogo do sistema, que é o
comportamento correto.

---

## Sprint 4 — Os celulares e as duas máquinas

**Duas horas.**

A superfície que ninguém lembra: celular conectado por cabo, pasta compartilhada
entre os dois computadores, acesso de um ao outro para consertar.

### Celular

```bash
# a depuração USB está habilitada e autorizada aqui?
adb devices 2>/dev/null
cat ~/.android/adbkey.pub 2>/dev/null | wc -l
```

Depuração USB autorizada num computador significa que aquele computador tem
acesso amplo ao telefone, e continua tendo até a autorização ser revogada.

- Revogar autorizações antigas: no telefone, Opções do desenvolvedor, "Revogar
  autorizações de depuração USB"
- Desligar a depuração quando não estiver usando
- Backup de fotos do celular vai para dentro do cofre da Sprint 2, não para a
  home em claro

### Entre as duas máquinas

Consertar o computador um do outro é acesso administrativo mútuo. Isso é uma
escolha de confiança legítima entre vocês — o que precisa existir é
consciência de que uma máquina comprometida alcança a outra.

```bash
# há acesso por SSH entre elas?
grep -rn "PermitRootLogin\|PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null
cat ~/.ssh/authorized_keys 2>/dev/null

# pastas compartilhadas na rede
systemctl is-active smbd nfs-server 2>/dev/null
```

Se houver SSH entre elas: chave em vez de senha, e frase secreta na chave.

### Contas separadas

Se as duas pessoas usam o mesmo usuário do sistema, tudo é comum, inclusive
navegador, chaves e histórico. Usuários separados na mesma máquina custam pouco
e separam o que precisa ser separado.

---

## Sprint 5 — Backup que sobrevive

**Três horas.**

Sem backup, criptografia vira armadilha: disco corrompeu, senha esquecida, e
não há de onde voltar. Esta sprint vem antes de qualquer coisa destrutiva.

### A regra das três cópias

Três cópias, em dois tipos de mídia, uma fora de casa.

```bash
sudo apt install borgbackup   # cifra, deduplica e versiona

borg init --encryption=repokey-blake2 /mnt/externo/backup
borg create --stats --progress /mnt/externo/backup::{hostname}-{now} \
     ~/Documentos ~/Cofre ~/.config ~/.ssh

# a cópia de fora de casa
borg init --encryption=repokey-blake2 ssh://usuario@servidor/./backup
```

O Borg cifra no destino. Isso importa: um backup em nuvem sem cifrar é a forma
mais provável de os seus dados vazarem, e a mais fácil de esquecer.

**Guarde a chave do repositório fora da máquina.** Sem ela, o backup não abre.

### Testar a restauração

Backup não testado não é backup.

```bash
borg extract --dry-run --list /mnt/externo/backup::NOME
# e uma vez de verdade, restaurando um arquivo em /tmp para conferir
```

Marque no calendário: testar a restauração a cada três meses.

---

## O que fica de fora, de propósito

- **Antivírus.** Em Linux de uso pessoal, o ganho não paga o custo.
- **Firewall fechando tudo.** A menos que a máquina sirva algo para a rede, o
  ganho é pequeno perto do incômodo. Vale conferir o que escuta (Sprint 1) e
  desligar o que não deveria estar lá.
- **Endurecimento do kernel, SELinux, AppArmor além do padrão.** Custo alto,
  ganho baixo para esta ameaça.

A ameaça real aqui não é um invasor remoto sofisticado. É a máquina perdida, o
backup vazado, o aplicativo com permissão demais e o celular autorizado num
computador que passou adiante.
