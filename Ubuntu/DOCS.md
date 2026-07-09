# Documentação Técnica — VPS Hardening Scripts

**Autor:** @andreluizfaustino  
**Repositório:** https://github.com/andreluizfaustino/devsecops-vps-startup

---

## Índice

- [Visão Geral da Arquitetura](#visão-geral-da-arquitetura)
- [01-startup.sh — Hardening do Servidor](#01-startupsh--hardening-do-servidor)
- [02-docker.sh — Docker + DOCKER-USER Firewall](#02-dockersh--docker--docker-user-firewall)
- [03-cloudflare-update-ufw.sh — Cloudflare IP Updater](#03-cloudflare-update-ufwsh--cloudflare-ip-updater)
- [_audit.sh — Auditoria de Saúde](#_auditsh--auditoria-de-saúde)
- [Serviços systemd](#serviços-systemd)
- [Arquivos Gerados](#arquivos-gerados)
- [Fluxo de Execução Recomendado](#fluxo-de-execução-recomendado)

---

## Visão Geral da Arquitetura

```
Internet
    │
    ├── Qualquer IP direto
    │       ├── porta 80/443 → DOCKER-USER: ACCEPT só IPs Cloudflare ✅
    │       ├── qualquer outra porta → DOCKER-USER: DROP ❌
    │       └── SSH, painéis, DBs → UFW: DENY ❌
    │
    └── Tailscale VPN (100.x.x.x)
            └── tudo → ACCEPT ✅ (admin e dispositivos autorizados)

Camadas de proteção (de fora para dentro):
  Cloudflare WAF → UFW (INPUT) → DOCKER-USER (FORWARD) → Fail2Ban → Aplicação

Por que duas camadas de firewall?
  UFW (INPUT)        → protege o HOST (SSH, serviços nativos)
  DOCKER-USER (FORWARD) → protege CONTAINERS (Docker bypassa UFW por padrão)
```

---

## 01-startup.sh — Hardening do Servidor

### Visão Geral

Script principal que aplica **15 fases de hardening** em um servidor Ubuntu recém-criado. Transforma uma VPS padrão em um servidor seguro para produção em ~4 minutos.

```bash
sudo bash 01-startup.sh
```

**Requisitos:** Ubuntu 22.04 LTS ou 24.04 LTS, acesso root, conexão com internet.

---

### Infraestrutura do Script

#### Sistema de Checkpoint
Antes de executar qualquer fase, verifica o arquivo `.startup-checkpoint`. Se interrompido, ao executar novamente oferece:
- **Continuar de onde parou** — refaz apenas as fases pendentes
- **Recomeçar do zero** — apaga checkpoint e reinicia
- **Sair**

#### Sistema de Logging
- `logs/startup-YYYYMMDD_HHMMSS.log` — log completo com timestamps
- `logs/startup-errors.log` — apenas erros

#### Configuração Salva
Respostas salvas em `.startup-config` (permissão 600). Recarregadas automaticamente em retomadas.

---

### Configuração Interativa

**Informações Obrigatórias:**
1. **Usuário SSH** — `root`, `ubuntu` ou customizado
2. **Senha** — solicitada apenas se não for root
3. **Porta SSH** — aceita 22 ou 1024-65535, padrão: `2222`
4. **SWAP** — tamanho em GB, mínimo 1GB, padrão: `2`
5. **Chave pública SSH** — conteúdo do `~/.ssh/id_ed25519.pub`

**Componentes Opcionais:**

| # | Componente | Padrão |
|---|---|---|
| [1] | Unattended Upgrades | S |
| [2] | Auditd | S |
| [3] | Logging Avançado | S |
| [4] | Bloqueio de Módulos de Kernel | S |

---

### As 15 Fases

#### FASE 1 — Configurar Usuário SSH
Cria ou usa usuário existente, define senha, adiciona ao grupo sudo.

#### FASE 2 — Timezone
Define `America/Sao_Paulo`, habilita sincronização NTP.

#### FASE 3 — Atualização do Sistema
`apt update` + `apt upgrade` + autoremove + autoclean.

#### FASE 4 — Unattended Upgrades *(opcional)*
Patches de segurança automáticos diários, sem reboot automático.

#### FASE 5 — Segurança do Kernel
ASLR máximo, ptrace restrito, core dumps desabilitados.

#### FASE 6 — Hardening de Rede + Performance
| Grupo | Efeito |
|---|---|
| Anti-spoofing, anti-redirect, anti-smurf | Impede spoofing e ataques ICMP |
| SYN cookies + tcp_rfc1337 | Proteção anti-SYN flood |
| Conntrack 1M conexões | Suporta alta carga sem travar |
| BBR congestion control | 2-25x mais throughput |
| TCP tuning (buffers 16MB, somaxconn 4096) | APIs de alto tráfego |
| File descriptors 1M | Conexões simultâneas |

#### FASE 7 — SWAP
Cria `/swap/swapfile` com tamanho configurado, persiste no `/etc/fstab`.

#### FASE 8 — Chave SSH
Instala chave pública em `~/.ssh/authorized_keys` com permissões corretas.

#### FASE 9 — Tailscale VPN ⚠️ *requer ação manual*
Instala, executa `tailscale up`, pausa para autenticação no navegador, captura IPs.

#### FASE 10 — SSH Hardening *(fase mais crítica)*
SSH passa a escutar **apenas** nos IPs do Tailscale:
- Desabilita cloud-init overrides
- Desabilita autenticação por senha
- Habilita apenas chave pública
- Algoritmos modernos: Ed25519, ChaCha20-Poly1305, curve25519
- Validação com `sshd -t` e rollback automático se falhar

#### FASE 11 — Fail2Ban
Jails `sshd` (ban permanente após 3 tentativas) e `sshd-ddos` (1h após 5 tentativas). Escopo: `/var/log/auth.log`.

#### FASE 12 — Firewall UFW
- Política padrão: DENY incoming, ALLOW outgoing
- Libera 80 e 443 publicamente (substituídos por Cloudflare-Only ao rodar `03`)
- Libera toda a interface `tailscale0`
- Logging medium

#### FASE 13 — Bloqueio de Módulos de Kernel *(opcional)*
Bloqueia: `dccp`, `sctp`, `rds`, `tipc`, `cramfs`, `jffs2`, `hfs`, `hfsplus`, `udf`. Segue CIS Benchmark.

#### FASE 14 — Auditd *(opcional)*
Monitora: `/etc/passwd`, `/etc/shadow`, `sshd_config`, `sudo`, `su`. Otimizado para ~1% overhead.

#### FASE 15 — Logging Avançado *(opcional)*
Journald persistente (500MB máx), logrotate para sudo.log, rsyslog ativo.

### Ao Final
Resumo no terminal, `server-info.txt` em `/root/`, **reboot automático em 10s**.

---

## 02-docker.sh — Docker + DOCKER-USER Firewall

### Visão Geral

Instala Docker Engine e configura o firewall `DOCKER-USER` para bloquear acesso direto a containers por IP, permitindo apenas Cloudflare (80/443) e Tailscale. Deve ser executado **após** o `01-startup.sh` e o reboot.

```bash
sudo bash 02-docker.sh
```

---

### Por que DOCKER-USER?

O Docker **bypassa o UFW** para tráfego de containers — ele injeta regras diretamente em `iptables FORWARD`. Isso significa que o UFW sozinho não protege containers. A chain `DOCKER-USER` é executada **antes** das regras do Docker no `FORWARD`, sendo o único ponto de controle confiável.

```
Internet → eth0 → FORWARD chain → DOCKER-USER (nosso controle) → DOCKER-FORWARD → container
                                                                  ↑
                                                        UFW não chega aqui
```

---

### Etapa 1/3 — Docker Engine

- Pergunta se deseja instalar o Docker
- Instala via repositório oficial apt:
  - `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`
- Habilita e inicia `docker.service`
- Adiciona usuário `ubuntu` ao grupo docker (se existir)
- Cria `/etc/docker/daemon.json`:

```json
{
  "ip": "127.0.0.1",
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
```

`"ip": "127.0.0.1"` faz containers sem bind explícito bindarem em localhost — não ficam expostos. Complementa o DOCKER-USER para containers com bind `0.0.0.0` (como Traefik).

---

### Etapa 2/3 — Script DOCKER-USER

Cria `/usr/local/bin/docker-user-firewall.sh` com a lógica de firewall:

```bash
# Regras aplicadas (em ordem):
1. ESTABLISHED,RELATED → ACCEPT    # respostas a conexões iniciadas por você
2. tailscale0 → ACCEPT             # tudo via Tailscale VPN
3. IPs Cloudflare :80 → ACCEPT     # lidos do UFW (se 03 já rodou)
   IPs Cloudflare :443 → ACCEPT    # fallback: abre para todos se UFW sem CF
4. eth0 → DROP                     # bloqueia todo o resto da internet
5. RETURN                          # tráfego interno entre containers: normal
```

**Lógica de IPs Cloudflare:**
O script lê os IPs diretamente do que o UFW já tem registrado (comentário `Cloudflare`). Não faz requisições à internet no boot. Se `03` ainda não rodou, o UFW não tem IPs Cloudflare → fallback abre 80/443 para todos temporariamente.

---

### Etapa 3/3 — Serviço systemd

Cria e habilita `docker-user-firewall.service`:
- `After=docker.service` → executa após Docker iniciar
- `Type=oneshot` + `RemainAfterExit=yes` → roda uma vez, permanece "ativo"
- Garante que as regras sejam reaplicadas em todo reboot

---

## 03-cloudflare-update-ufw.sh — Cloudflare IP Updater

### Visão Geral

Atualiza os IPs da Cloudflare no UFW e no DOCKER-USER, ativando o modo Cloudflare-Only. Após a primeira execução, acesso direto por IP às portas 80/443 é bloqueado no nível de rede.

```bash
sudo bash 03-cloudflare-update-ufw.sh
```

---

### Funcionamento

**1. Pergunta inicial** — confirma se deseja verificar/atualizar IPs.

**2. Busca IPs oficiais da Cloudflare:**
```
https://www.cloudflare.com/ips-v4  → 15 ranges IPv4
https://www.cloudflare.com/ips-v6  → 7 ranges IPv6
```

**3. Lê regras Cloudflare atuais do UFW** — extrai IPs de regras com comentário `Cloudflare`.

**4. Calcula diff** — IPs a adicionar e IPs obsoletos a remover.

**5. Exibe resumo detalhado** antes de qualquer ação.

**6. Pede confirmação** — só aplica após `s` explícito.

**7. Remove regras públicas** — garante que 80/443 só aceitem Cloudflare.

**8. Remove IPs obsoletos** + **adiciona IPs novos** no UFW.

**9. Atualiza DOCKER-USER** — reinicia `docker-user-firewall.service`, que lê os novos IPs do UFW e reaplicaca todas as regras.

**10. Pergunta sobre timer mensal** — se ainda não existir, oferece criar atualização automática.

---

### Modo Cloudflare-Only: como funciona

Após rodar o `03`, qualquer acesso que **não venha de um IP Cloudflare** é dropado no `DOCKER-USER` antes de chegar nos containers:

| Origem | Porta | Resultado |
|---|---|---|
| IP Cloudflare | 80 ou 443 | ACCEPT → chega no Traefik |
| IP qualquer direto | 80 ou 443 | DROP no DOCKER-USER |
| IP qualquer direto | qualquer outra | DROP no DOCKER-USER |
| Tailscale VPN | qualquer | ACCEPT → acesso total |

---

### Timer Mensal Automático (opcional)

Ao final da execução, o script oferece criar:

| Arquivo | Função |
|---|---|
| `/usr/local/bin/cloudflare-update-firewall.sh` | Script não-interativo (sem prompts) |
| `cloudflare-update-firewall.service` | Executa o script via systemd |
| `cloudflare-update-firewall.timer` | Dispara mensalmente, `Persistent=true` |

`Persistent=true` garante que, se a VPS estiver desligada no dia agendado, o timer roda na próxima vez que ligar.

**Quando rodar o `03` manualmente no futuro**, o `docker-user-firewall.service` é reiniciado automaticamente — não é preciso rodar nenhum script adicional.

---

## _audit.sh — Auditoria de Saúde

### Visão Geral

Valida se todas as configurações dos scripts anteriores foram aplicadas corretamente. Gera relatório com score percentual e log datado.

```bash
sudo bash _audit.sh
```

---

### Seções Verificadas

| Seção | Verificações |
|---|---|
| Sistema Base | Timezone, NTP, SWAP, Unattended Upgrades |
| Kernel/sysctl | 17+ parâmetros de segurança e performance |
| Módulos de Kernel | 9 módulos bloqueados (opcional) |
| SSH Hardening | PasswordAuth, PubkeyAuth, PermitRootLogin, ListenAddress, criptografia, cloud-init |
| Tailscale VPN | Instalado, serviço ativo, conectado |
| Firewall UFW | Ativo, DENY incoming, IPv6, logging medium, Tailscale liberado, IPs Cloudflare |
| Fail2Ban | Instalado, serviço ativo, jail sshd |
| Auditd | Instalado, serviço ativo, regras carregadas (opcional) |
| Docker | Instalado, serviço ativo, daemon.json bind 127.0.0.1, API não exposta |
| DOCKER-USER Firewall | Serviço enabled + ativo, chain com regras, modo Cloudflare-Only, timer mensal |
| Logging | Journald limite, rsyslog |
| Exposição de Portas | Portas inesperadas abertas, SSH no IP público |

### Output

```
✅ PASS  72/75 verificações
❌ FAIL  0 verificações críticas
⚠️  WARN  3 avisos (opcionais/menores)

Score: 96% — Excelente
```

- Exit code `0` → sem FAILs
- Exit code `1` → há FAILs críticos
- Log salvo em `logs/audit-YYYYMMDD_HHMMSS.log`

---

## Serviços systemd

### `docker-user-firewall.service`
- **Criado por:** `02-docker.sh`
- **Script:** `/usr/local/bin/docker-user-firewall.sh`
- **Executa:** no boot, após `docker.service`
- **Lógica:** lê IPs Cloudflare do UFW, aplica `DOCKER-USER`

### `cloudflare-update-firewall.service`
- **Criado por:** `03-cloudflare-update-ufw.sh` (opcional)
- **Script:** `/usr/local/bin/cloudflare-update-firewall.sh`
- **Executa:** chamado pelo timer

### `cloudflare-update-firewall.timer`
- **Criado por:** `03-cloudflare-update-ufw.sh` (opcional)
- **Dispara:** mensalmente, `Persistent=true`
- **Efeito:** atualiza UFW + reinicia `docker-user-firewall.service`

```
Boot:
  docker.service → docker-user-firewall.service
                        ↓ lê IPs do UFW → aplica DOCKER-USER

Mensalmente:
  cloudflare-update-firewall.timer
    → cloudflare-update-firewall.service
        → atualiza UFW com IPs Cloudflare
        → reinicia docker-user-firewall.service
            → DOCKER-USER reaplica com IPs atualizados
```

---

## Arquivos Gerados

### pelo 01-startup.sh

| Arquivo | Descrição |
|---|---|
| `logs/startup-YYYYMMDD.log` | Log completo de execução |
| `logs/startup-errors.log` | Apenas erros |
| `/root/server-info.txt` | Resumo de acesso e configuração |
| `/etc/sysctl.d/60-net.conf` | Parâmetros de rede e performance |
| `/etc/sysctl.d/60-conntrack.conf` | Parâmetros do conntrack |
| `/etc/sysctl.d/60-aslr.conf` | ASLR |
| `/etc/sysctl.d/60-yama.conf` | ptrace |
| `/etc/sysctl.d/60-coredump.conf` | Core dumps |
| `/etc/modules-load.d/nf_conntrack.conf` | Carga do conntrack no boot |
| `/etc/modprobe.d/blacklist-hardening.conf` | Módulos de kernel bloqueados |
| `/etc/ssh/sshd_config.backup.*` | Backup datado do SSH original |
| `/etc/fail2ban/jail.local` | Jails do Fail2Ban |
| `/etc/audit/rules.d/hardening.rules` | Regras do Auditd |
| `/swap/swapfile` | Arquivo de swap |

### pelo 02-docker.sh

| Arquivo | Descrição |
|---|---|
| `/etc/docker/daemon.json` | Configuração do Docker daemon (bind 127.0.0.1) |
| `/usr/local/bin/docker-user-firewall.sh` | Script de regras DOCKER-USER |
| `/etc/systemd/system/docker-user-firewall.service` | Serviço systemd |

### pelo 03-cloudflare-update-ufw.sh

| Arquivo | Descrição |
|---|---|
| `/usr/local/bin/cloudflare-update-firewall.sh` | Script não-interativo (timer) |
| `/etc/systemd/system/cloudflare-update-firewall.service` | Serviço systemd |
| `/etc/systemd/system/cloudflare-update-firewall.timer` | Timer mensal |

---

## Fluxo de Execução Recomendado

```
1. Provisionar VPS Ubuntu 22.04 ou 24.04

2. Acessar via console web ou SSH como root

3. git clone https://github.com/andreluizfaustino/devsecops-vps-startup.git
   cd devsecops-vps-startup/Ubuntu

4. sudo bash 01-startup.sh
   → Configurar interativamente (usuário, porta, swap, chave SSH, opcionais)
   → Autenticar Tailscale no navegador quando solicitado
   → Aguardar reboot automático (~4 min)

5. Conectar via Tailscale
   ssh ubuntu@<IP_TAILSCALE> -p <PORTA>

6. sudo bash 02-docker.sh
   → Confirmar instalação do Docker
   → Docker instalado + DOCKER-USER configurado + serviço systemd ativo

7. sudo bash 03-cloudflare-update-ufw.sh
   → Confirmar atualização de IPs
   → IPs Cloudflare aplicados no UFW + DOCKER-USER
   → Configurar timer mensal (recomendado: S)
   → A partir daqui: acesso direto por IP às portas 80/443 é bloqueado

8. sudo bash _audit.sh
   → Validar score (esperado: ~96-97%)

Manutenção futura:
   → Atualizar IPs Cloudflare: sudo bash 03-cloudflare-update-ufw.sh
   → Health check:             sudo bash _audit.sh
   → Logs do firewall:         journalctl -u docker-user-firewall.service
   → Logs do timer mensal:     journalctl -u cloudflare-update-firewall.service
   → Nova VPS: git pull && repetir passos 4-8
```
