# Documentação Técnica — VPS Hardening Scripts

**Autor:** @andreluizfaustino  
**Repositório:** https://github.com/andreluizfaustino/devsecops-vps-startup

---

## Índice

- [Visão Geral da Arquitetura](#visão-geral-da-arquitetura)
- [01-startup.sh — Hardening do Servidor](#01-startupsh--hardening-do-servidor)
- [02-docker-and-netdata.sh — Docker e Monitoramento](#02-docker-and-netdatash--docker-e-monitoramento)
- [03-cloudflare-update-ufw.sh — Cloudflare IP Updater](#03-cloudflare-update-ufwsh--cloudflare-ip-updater)
- [\_audit.sh — Auditoria de Saúde](#_auditsh--auditoria-de-saúde)
- [Arquivos Gerados](#arquivos-gerados)
- [Fluxo de Execução Recomendado](#fluxo-de-execução-recomendado)

---

## Visão Geral da Arquitetura

```
Internet
    │
    ├── IP público (ex: SEU_IP_PUBLICO)
    │       ├── porta 80/443 → só IPs Cloudflare ✅
    │       └── qualquer outra porta → DROP ❌
    │
    └── Tailscale VPN (ex: 100.x.x.x)
            └── tudo → ALLOW ✅ (admin e dispositivos autorizados)

Camadas de proteção (de fora para dentro):
  Cloudflare WAF → UFW Firewall → CrowdSec (IPS) → Fail2Ban (SSH) → Aplicação
```

---

## 01-startup.sh — Hardening do Servidor

### Visão Geral

Script principal que aplica **16 fases de hardening** em um servidor Ubuntu recém-criado. Transforma uma VPS padrão em um servidor seguro para produção em ~4 minutos.

```bash
sudo bash 01-startup.sh
```

**Requisitos:** Ubuntu 22.04 LTS ou 24.04 LTS, acesso root, conexão com internet.

---

### Infraestrutura do Script

#### Sistema de Checkpoint
Antes de executar qualquer fase, verifica o arquivo `.startup-checkpoint`. Se interrompido (queda de conexão, erro, Ctrl+C), ao ser executado novamente oferece:
- **Continuar de onde parou** — refaz apenas as fases pendentes
- **Recomeçar do zero** — apaga checkpoint e reinicia
- **Sair**

Cada fase é registrada no checkpoint imediatamente após conclusão.

#### Sistema de Logging
Todos os comandos são gravados em tempo real:
- `logs/startup-YYYYMMDD_HHMMSS.log` — log completo com timestamps
- `logs/startup-errors.log` — apenas erros

#### Progress Bar
Após cada fase, exibe visualmente o progresso:
```
Progresso: [████████████████░░░░░░░░] 50% (8/16 fases)
```

#### Configuração Salva
Todas as respostas são salvas em `.startup-config` (permissão 600). Se o checkpoint existir, o arquivo é carregado automaticamente sem perguntar novamente.

---

### Configuração Interativa

Executada **antes** de qualquer fase. Coleta 5 informações obrigatórias e 5 opcionais.

#### Informações Obrigatórias

**1. Usuário SSH**
- `root` — mantém acesso root apenas com chave SSH
- `ubuntu` — cria ou usa usuário ubuntu existente, adicionado ao grupo sudo
- `customizado` — qualquer nome válido (letras minúsculas, números, `_`, `-`, máx. 32 chars)

**2. Senha do usuário**
Solicitada apenas se não for root. Confirmação dupla. Senha vazia rejeitada.

**3. Porta SSH**
Aceita porta `22` ou `1024-65535`. Padrão: `2222`.

**4. Tamanho do SWAP**
Em gigabytes. Mínimo: 1GB. Padrão: `2`.

**5. Chave pública SSH**
Cole o conteúdo do `~/.ssh/id_ed25519.pub`. Validação: deve começar com `ssh-rsa`, `ssh-ed25519` ou `ssh-ecdsa`.

#### Componentes Opcionais

| # | Componente | Padrão | Tempo estimado |
|---|---|---|---|
| [1] | Unattended Upgrades | S | ~2 min |
| [2] | Auditd | S | ~2 min |
| [4] | Logging Avançado | S | ~5s |
| [6] | CrowdSec | S | ~3 min |
| [7] | Bloqueio de Módulos de Kernel | S | ~5s |

---

### As 16 Fases

#### FASE 1 — Configurar Usuário SSH
**Checkpoint:** `ubuntu_password`

- Se não for root: verifica se o usuário já existe
  - Se não existir: cria com `useradd -m -s /bin/bash -G sudo`
  - Se já existir: apenas atualiza a senha
- Define a senha via `chpasswd`
- Se for root: registra que nenhuma ação é necessária

---

#### FASE 2 — Timezone
**Checkpoint:** `timezone`

- Define timezone para `America/Sao_Paulo` via `timedatectl set-timezone`
- Habilita sincronização automática: `timedatectl set-ntp true`

---

#### FASE 3 — Atualização do Sistema
**Checkpoint:** `system_update`

- Remove repositórios problemáticos conhecidos (ex: Monarx da Hostinger)
- `apt update` — atualiza lista de pacotes (continua mesmo com erros)
- `apt upgrade -y` com `--force-confdef --force-confold`
- `apt autoremove` — remove dependências órfãs
- `apt autoclean` — limpa cache de pacotes

---

#### FASE 4 — Unattended Upgrades *(opcional)*
**Checkpoint:** `unattended_upgrades`

- Instala `unattended-upgrades` e `apt-listchanges`
- Configura `/etc/apt/apt.conf.d/50unattended-upgrades`:
  - Aplica apenas `*-security` (não updates gerais)
  - Remove dependências não utilizadas automaticamente
  - **Reboot automático desabilitado** (decisão manual do admin)
- Configura `/etc/apt/apt.conf.d/20auto-upgrades`:
  - Atualiza lista diariamente
  - Instala patches de segurança diariamente
  - Limpa cache semanalmente

---

#### FASE 5 — Segurança do Kernel
**Checkpoint:** `kernel_security`

Cria arquivos em `/etc/sysctl.d/`:

| Arquivo | Parâmetro | Valor | Efeito |
|---|---|---|---|
| `60-aslr.conf` | `kernel.randomize_va_space` | 2 | ASLR máximo — randomiza endereços de memória, dificulta exploits |
| `60-yama.conf` | `kernel.yama.ptrace_scope` | 1 | Restringe ptrace — impede processo de espionar outro sem ser pai direto |
| `60-coredump.conf` | `fs.suid_dumpable` | 0 | Desabilita core dumps — impede senha/chaves em arquivos de crash |
| `limits.conf` | `* hard core` | 0 | Desabilita core dumps a nível de usuário |

---

#### FASE 6 — Hardening de Rede + Performance Tuning
**Checkpoint:** `network_hardening`

Cria `/etc/sysctl.d/60-net.conf` com os seguintes grupos de parâmetros:

##### Segurança de Rede

| Parâmetro | Valor | Efeito |
|---|---|---|
| `net.ipv4.ip_forward` | 0 | Desabilita roteamento entre interfaces |
| `net.ipv4.conf.all.send_redirects` | 0 | Não envia ICMP redirects |
| `net.ipv4.conf.default.send_redirects` | 0 | Idem para novas interfaces |
| `net.ipv4.conf.all.accept_redirects` | 0 | Ignora ICMP redirects recebidos (IPv4) |
| `net.ipv4.conf.default.accept_redirects` | 0 | Idem |
| `net.ipv6.conf.all.accept_redirects` | 0 | Ignora ICMP redirects (IPv6) |
| `net.ipv6.conf.default.accept_redirects` | 0 | Idem |
| `net.ipv4.conf.all.rp_filter` | 1 | Reverse Path Filter — descarta pacotes com IP forjado (anti-spoofing) |
| `net.ipv4.conf.default.rp_filter` | 1 | Idem para novas interfaces |
| `net.ipv4.icmp_ignore_bogus_error_responses` | 1 | Ignora respostas ICMP inválidas/malformadas |
| `net.ipv4.icmp_echo_ignore_broadcasts` | 1 | Não responde a pings de broadcast (anti-smurf) |
| `net.ipv4.icmp_ratelimit` | 100 | Limita ICMP flood a 100 pacotes por 4 segundos |
| `net.ipv4.tcp_syncookies` | 1 | SYN cookies — protege contra SYN flood sem descartar conexões legítimas |
| `net.ipv4.tcp_rfc1337` | 1 | Proteção contra TIME-WAIT assassination (RFC 1337) |
| `net.ipv4.tcp_timestamps` | 0 | Desabilita timestamps TCP — evita fingerprinting do uptime |
| `net.ipv4.tcp_synack_retries` | 2 | Reduz tentativas de SYN-ACK — libera recursos mais rápido em ataques |

##### Performance TCP

| Parâmetro | Valor | Efeito |
|---|---|---|
| `net.core.somaxconn` | 4096 | Fila máxima de conexões TCP pendentes |
| `net.ipv4.tcp_max_syn_backlog` | 8192 | Fila de SYN half-open connections |
| `net.core.rmem_max` / `wmem_max` | 16MB | Buffers máximos de leitura/escrita |
| `net.ipv4.tcp_rmem` / `tcp_wmem` | 4096/87380/16MB | Buffers adaptativos por socket |
| `net.ipv4.tcp_tw_reuse` | 1 | Reutiliza sockets em TIME_WAIT |
| `net.ipv4.tcp_fin_timeout` | 15s | Reduz tempo de espera para fechar conexão |
| `net.ipv4.tcp_max_tw_buckets` | 400000 | Máximo de sockets em TIME_WAIT simultâneos |
| `net.ipv4.tcp_fastopen` | 3 | TCP Fast Open — reduz latência da primeira conexão |
| `net.ipv4.tcp_keepalive_time` | 600s | Inicia keepalive após 10 min de inatividade |
| `net.ipv4.tcp_keepalive_intvl` | 10s | Intervalo entre probes |
| `net.ipv4.tcp_keepalive_probes` | 6 | Probes antes de declarar conexão morta |

##### File Descriptors

| Parâmetro | Valor | Efeito |
|---|---|---|
| `fs.file-max` | 2.097.152 | Máximo global de file descriptors |
| `fs.nr_open` | 2.097.152 | Máximo por processo |

Configura também em `/etc/security/limits.conf` e `/etc/systemd/system.conf` com `DefaultLimitNOFILE=1048576`.

##### BBR Congestion Control
Verifica suporte com `modprobe tcp_bbr`. Se disponível:
```
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```
BBR (Google) oferece 2-25x mais throughput que o CUBIC padrão em condições de perda de pacotes.

##### Conntrack — Proteção Anti-DDoS por Flood de Conexões
Garante carga do módulo no boot via `/etc/modules-load.d/nf_conntrack.conf`. Configura em `/etc/sysctl.d/60-conntrack.conf`:

| Parâmetro | Valor | Efeito |
|---|---|---|
| `nf_conntrack_max` | 1.048.576 | Tabela suporta 1 milhão de conexões simultâneas |
| `tcp_timeout_established` | 86400s | Conexões estabelecidas expiram em 24h |
| `tcp_timeout_syn_recv` | 15s | Half-open connections expiram em 15s |
| `tcp_timeout_time_wait` | 15s | TIME_WAIT libera slot em 15s |
| `tcp_timeout_close_wait` | 30s | CLOSE_WAIT libera slot em 30s |

> Sem essa configuração, um flood de conexões pode esgotar a tabela do conntrack e travar o servidor completamente.

---

#### FASE 7 — SWAP
**Checkpoint:** `swap`

- Desativa e remove swap existente se houver
- Cria `/swap/swapfile` com `dd` no tamanho configurado
- `chmod 600` — permissão obrigatória
- `mkswap` + `swapon` — formata e ativa
- Adiciona entrada no `/etc/fstab` para persistência após reboot

---

#### FASE 8 — Chave SSH
**Checkpoint:** `ssh_key`

- Cria `~/.ssh/` com `chmod 700`
- Escreve chave pública em `~/.ssh/authorized_keys`
- `chmod 600` no arquivo
- `chown -R USUARIO:USUARIO` (se não for root)

---

#### FASE 9 — Tailscale VPN ⚠️ *requer ação manual*
**Checkpoint:** `tailscale`

- Instala via `https://tailscale.com/install.sh`
- Executa `tailscale up` → exibe URL de autenticação
- **Pausa** — admin abre URL no navegador e pressiona ENTER
- Captura `TAILSCALE_IPV4` e `TAILSCALE_IPV6` via `tailscale ip`
- Salva IPs no `.startup-config` para fases seguintes
- Aborta se não conectar (fase 10 depende do IP Tailscale)

---

#### FASE 10 — SSH Hardening *(fase mais crítica)*
**Checkpoint:** `ssh_config`

SSH passa a escutar **apenas** nos IPs do Tailscale — invisível no IP público.

**Desabilita cloud-init:**
- `50-cloud-init.conf` → `.disabled`
- `60-cloudimg-settings.conf` → `.disabled`

**Remove configurações antigas** do `sshd_config` (linhas ativas e comentadas).

**Cria backup:** `sshd_config.backup.YYYYMMDD_HHMMSS`

**Aplica configuração segura:**
```
ListenAddress 127.0.0.1
ListenAddress <TAILSCALE_IPV4>
ListenAddress <TAILSCALE_IPV6>

Port <SSH_PORT>
Protocol 2

PubkeyAuthentication yes
PasswordAuthentication no
ChallengeResponseAuthentication no
PermitEmptyPasswords no
PermitRootLogin no  (ou prohibit-password se usuário=root)
AllowUsers <SSH_USER>

LoginGraceTime 30
MaxAuthTries 3
MaxSessions 2
MaxStartups 10:30:60

ClientAliveInterval 300
ClientAliveCountMax 2
TCPKeepAlive no

X11Forwarding no
PermitUserEnvironment no
GatewayPorts no
PermitTunnel no

# Algoritmos de criptografia modernos apenas
KexAlgorithms curve25519-sha256,...
Ciphers chacha20-poly1305,...
MACs hmac-sha2-512-etm,...
```

**Validação com `sshd -t`** antes de reiniciar. **Rollback automático** se falhar.

---

#### FASE 11 — Fail2Ban
**Checkpoint:** `fail2ban`

Cria `/etc/fail2ban/jail.local` com dois jails:

**[sshd]:**
```
maxretry = 3
bantime = -1     (ban permanente)
findtime = 600s
```

**[sshd-ddos]:**
```
maxretry = 5
bantime = 3600s  (1 hora)
```

Escopo: `/var/log/auth.log` (tentativas de login SSH)

---

#### FASE 12 — Firewall UFW
**Checkpoint:** `firewall_ufw`

- `IPV6=yes` em `/etc/default/ufw`
- `ufw --force reset` — limpa regras existentes
- Políticas: `DENY incoming`, `ALLOW outgoing`
- Libera 80 e 443 publicamente (substituídos pela Cloudflare ao rodar `03-cloudflare-update-ufw.sh`)
- Libera toda a interface `tailscale0`
- `ufw --force enable`
- `ufw logging medium` — loga pacotes bloqueados por regra e por política padrão

---

#### FASE 13 — CrowdSec *(opcional)*
**Checkpoint:** `crowdsec`

- Adiciona repositório oficial via `install.crowdsec.net`
- `apt install crowdsec` — motor principal
- `apt install crowdsec-firewall-bouncer-iptables` — bouncer que bloqueia IPs no firewall

**Registro da API key (crítico):**
```bash
bouncer_key=$(cscli bouncers add firewall-bouncer -o raw)
sed -i "s/^api_key:.*/api_key: ${bouncer_key}/" \
    /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml
```

**Collections instaladas:**
- `crowdsecurity/linux` — regras gerais para servidores Linux
- `crowdsecurity/traefik` — proteção para tráfego Traefik
- `crowdsecurity/nginx` — proteção para tráfego Nginx

**Comparação com Fail2Ban:**

| | Fail2Ban | CrowdSec |
|---|---|---|
| Escopo | SSH brute force (auth.log) | HTTP, bots, scanners, IPs de reputação ruim |
| Inteligência | Local | Colaborativa (milhares de servidores) |
| Bloqueio | Fail2Ban chain | iptables/nftables via bouncer |
| Conflito | Nenhum — escopos distintos | Nenhum |

---

#### FASE 14 — Bloqueio de Módulos de Kernel *(opcional)*
**Checkpoint:** `kernel_modules`

Cria `/etc/modprobe.d/blacklist-hardening.conf`:

**Protocolos de rede bloqueados:**
| Módulo | Protocolo | Motivo |
|---|---|---|
| `dccp` | Datagram Congestion Control | Nunca usado em servidores, histórico de CVEs |
| `sctp` | Stream Control Transmission | Apenas telecomunicações |
| `rds` | Reliable Datagram Sockets | Apenas clusters Oracle RAC |
| `tipc` | Transparent Inter-Process Comm | Apenas clusters especializados |

**Filesystems bloqueados:**
| Módulo | Filesystem | Motivo |
|---|---|---|
| `cramfs` | Compressed ROM FS | Sistemas embarcados |
| `freevxfs` | Veritas FS | UNIX legado |
| `jffs2` | Journalling Flash FS | Dispositivos embarcados |
| `hfs` | HFS Mac OS clássico | Nunca usado em servidores Linux |
| `hfsplus` | HFS+ Mac OS X | Idem |
| `udf` | Universal Disk Format | DVD/Blu-ray |

`update-initramfs -u` garante aplicação no próximo boot. Segue recomendações CIS Benchmark.

---

#### FASE 15 — Auditd *(opcional)*
**Checkpoint:** `auditd`

Configura `/etc/audit/rules.d/hardening.rules` com **5 regras otimizadas** (~1% overhead):

```
# Alterações em arquivos críticos
-w /etc/passwd          -p wa -k passwd_changes
-w /etc/shadow          -p wa -k shadow_changes
-w /etc/ssh/sshd_config -p wa -k sshd_changes

# Execução de comandos privilegiados
-w /usr/bin/sudo -p x -k sudo_execution
-w /bin/su       -p x -k su_execution
```

Configuração do `auditd.conf`:
- `max_log_file = 50` MB por arquivo
- `num_logs = 10` rotações
- `max_log_file_action = rotate`

Logs em `/var/log/audit/audit.log`.

> Regras pesadas omitidas intencionalmente: monitoramento de `/home`, syscalls `execve`, mudanças de permissão — impacto de performance inaceitável para APIs.

---

#### FASE 16 — Logging Avançado *(opcional)*
**Checkpoint:** `logging`

**Logrotate** — `/etc/logrotate.d/sudo`:
```
/var/log/sudo.log {
    weekly / rotate 4 / compress / missingok / notifempty
}
```

**Journald** — `/etc/systemd/journald.conf`:
- `Storage=persistent` — persiste logs entre reboots
- `SystemMaxUse=500M` — limita uso de disco a 500MB

---

### Ao Final do Script

**Resumo no terminal** com todos os valores configurados.

**`/root/server-info.txt`** — arquivo com informações de acesso:
- Comando SSH: `ssh USUARIO@IP_TAILSCALE -p PORTA`
- IPs Tailscale (IPv4 e IPv6)
- Status do firewall e componentes

**Reboot automático em 10 segundos** — necessário para:
- Módulos bloqueados não carregarem mais
- `nf_conntrack` iniciar com valores corretos
- File descriptor limits do systemd entrarem em efeito
- Configurações do kernel serem consolidadas

---

## 02-docker-and-netdata.sh — Docker e Monitoramento

### Visão Geral

Instala Docker Engine e sobe o Netdata via Docker Compose com integrações para CrowdSec, Fail2Ban e UFW/iptables. Deve ser executado **após** o `01-startup.sh` e o reboot.

```bash
sudo bash 02-docker-and-netdata.sh
```

---

### Etapa 1/4 — Docker

- Verifica se Docker já está instalado (`docker info`)
  - Se já existir: exibe versão e pula a instalação
  - Se não existir: instala via `curl -fsSL https://get.docker.com | sh`
- Habilita e inicia o serviço `docker`
- Adiciona o usuário `ubuntu` ao grupo `docker` (evita uso de sudo em cada comando)
- Valida com `docker info`

---

### Etapa 2/4 — Netdata

Cria `/opt/netdata/docker-compose.yml` e `/opt/netdata/config/` e sobe o container.

**Configuração do container:**
```yaml
image: netdata/netdata:latest
network_mode: host       # acesso direto às interfaces do host
pid: host                # acesso aos processos do host
cap_add:
  - SYS_PTRACE           # leitura de processos
  - SYS_ADMIN            # acesso a subsistemas do kernel
  - NET_ADMIN            # acesso a regras de rede (iptables)
security_opt:
  - apparmor:unconfined
```

**Volumes montados:**
| Volume | Propósito |
|---|---|
| `./config:/etc/netdata` | Configurações persistentes (bind mount) |
| `/proc:/host/proc:ro` | Métricas do host (CPU, RAM, processos) |
| `/sys:/host/sys:ro` | Métricas de hardware |
| `/:/host/root:ro` | Acesso ao sistema de arquivos do host |
| `/var/run/docker.sock:ro` | Métricas de containers Docker |
| `/var/run/fail2ban/fail2ban.sock:ro` | Integração Fail2Ban |

**Cobertura nativa automática:**
- Host: CPU, RAM, disco, rede, processos, file descriptors
- Docker: CPU, RAM, I/O por container
- Tailscale: tráfego da interface `tailscale0`
- Conntrack: uso da tabela de conexões (configurada para 1M)
- Systemd: status dos serviços (fail2ban, crowdsec, auditd, tailscaled)

**Acesso:** `http://<IP_TAILSCALE>:19999` — porta protegida pelo UFW, só acessível via Tailscale.

---

### Etapa 3/4 — Integração CrowdSec

Se o CrowdSec estiver instalado:
1. Remove bouncer antigo `netdata-bouncer` se existir
2. Cria novo bouncer: `cscli bouncers add netdata-bouncer -o raw`
3. Cria `/opt/netdata/config/go.d/crowdsec.conf`:
```yaml
jobs:
  - name: local
    url: http://localhost:8080
    credentials:
      api_key: <API_KEY_GERADA>
```
4. Reinicia o container para aplicar

**Métricas disponíveis via Prometheus** (autodiscovery na porta 6060):
- `cs_filesource` — linhas de log lidas por segundo
- `cs_lapi` — requests à API local (bouncers e máquinas)
- `cs_parser` — parsing de logs
- `cs_decisions` — decisões ativas (bans)

---

### Etapa 4/4 — Integração UFW/iptables + Fail2Ban

**UFW/iptables** — cria `/opt/netdata/config/go.d/iptables.conf`:
```yaml
jobs:
  - name: filter
    tables:
      - name: filter
        chains: [INPUT, FORWARD, OUTPUT]
```
> Nota: Ubuntu 22.04+ usa nftables como backend. O Conntrack em `Network > Firewall > Conntrack` mostra conexões ativas. Para DROPs do UFW seria necessário exportar logs do UFW via log parser.

**Fail2Ban** — cria `/opt/netdata/config/go.d/fail2ban.conf`:
```yaml
jobs:
  - name: local
    socket: /var/run/fail2ban/fail2ban.sock
```

---

## 03-cloudflare-update-ufw.sh — Cloudflare IP Updater

### Visão Geral

Script de manutenção que sincroniza as regras do UFW com os ranges de IPs mais recentes da Cloudflare. Deve ser executado **manualmente** pelo administrador sempre que quiser atualizar ou na primeira vez após o `01-startup.sh`.

```bash
sudo bash 03-cloudflare-update-ufw.sh
```

---

### Funcionamento

**1. Busca IPs atuais da Cloudflare:**
```
https://www.cloudflare.com/ips-v4  (15 ranges IPv4)
https://www.cloudflare.com/ips-v6  (7 ranges IPv6)
```

**2. Lê regras Cloudflare atuais do UFW** — extrai IPs de regras com comentário `Cloudflare`.

**3. Calcula o diff:**
- IPs novos não presentes no UFW → lista para adicionar
- IPs no UFW que não estão na lista nova → lista para remover

**4. Exibe resumo detalhado** antes de qualquer ação:
```
IPs atualmente no UFW (Cloudflare): 44
IPs na lista atual da Cloudflare:   46

❌ IPs a REMOVER (1):
   − 198.41.128.0/17

✅ IPs a ADICIONAR (3):
   + 103.21.244.0/22
   ...
```

**5. Pede confirmação** — só aplica após `s` explícito.

**6. Remove regras públicas** (`80/tcp ALLOW Anywhere`) — garante que somente Cloudflare acesse 80/443.

**7. Remove IPs obsoletos** do UFW (de trás para frente para não deslocar índices).

**8. Adiciona novos IPs** com comentário `Cloudflare IPv4` ou `Cloudflare IPv6`.

**9. Exibe resultado** com total de regras ativas.

---

### Quando rodar

- **Primeira vez** após `01-startup.sh` — ativa o modo Cloudflare-Only
- **Periodicamente** (recomendado mensal) — a Cloudflare ocasionalmente adiciona/remove ranges
- **Quando o audit mostrar** mudança no número de regras esperadas

---

## _audit.sh — Auditoria de Saúde

### Visão Geral

Script de validação que verifica se todas as configurações dos scripts anteriores foram aplicadas corretamente. Gera um relatório com score percentual.

```bash
sudo bash _audit.sh
```

---

### Seções Verificadas

| Seção | Verificações |
|---|---|
| Sistema Base | Timezone, NTP, SWAP, Unattended Upgrades |
| Kernel/sysctl | 17 parâmetros de segurança e performance |
| Módulos de Kernel | 9 módulos bloqueados |
| SSH Hardening | PasswordAuth, PubkeyAuth, PermitRootLogin, ListenAddress, criptografia, cloud-init |
| Tailscale VPN | Instalado, serviço ativo, conectado |
| Firewall UFW | Ativo, DENY incoming, IPv6, logging medium, Tailscale, regras Cloudflare |
| Fail2Ban | Instalado, serviço ativo, jail sshd |
| CrowdSec | Instalado, serviço ativo, bouncer ativo, 3 collections |
| Auditd | Instalado, serviço ativo, regras carregadas |
| Docker | Instalado, serviço ativo, API não exposta |
| Netdata | Container rodando, URL Tailscale, compose file |
| Logging | Journald limite, rsyslog |
| Exposição de Portas | Portas inesperadas abertas, SSH no IP público |

### Output

```
✅ PASS  71/73 verificações
❌ FAIL  0 verificações críticas
⚠️  WARN  2 avisos (opcionais/menores)

Score: 97% — Excelente
```

- Exit code `0` → sem FAILs
- Exit code `1` → há FAILs críticos
- Log salvo em `logs/audit-YYYYMMDD.log`

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

### pelo 02-docker-and-netdata.sh

| Arquivo | Descrição |
|---|---|
| `/opt/netdata/docker-compose.yml` | Compose do Netdata |
| `/opt/netdata/config/go.d/crowdsec.conf` | Integração CrowdSec |
| `/opt/netdata/config/go.d/fail2ban.conf` | Integração Fail2Ban |
| `/opt/netdata/config/go.d/iptables.conf` | Integração iptables |

---

## Fluxo de Execução Recomendado

```
1. Provisionar VPS Ubuntu (22.04 ou 24.04)

2. Acessar via console web ou SSH temporário como root

3. git clone https://github.com/andreluizfaustino/devsecops-vps-startup.git
   cd devsecops-vps-startup/Ubuntu

4. bash 01-startup.sh
   → Configurar interativamente
   → Autenticar Tailscale no navegador
   → Aguardar reboot automático (~4 min)

5. Conectar via Tailscale
   ssh ubuntu@<IP_TAILSCALE> -p <PORTA>

6. bash 02-docker-and-netdata.sh
   → Instala Docker
   → Sobe Netdata com integrações
   → Acesso: http://<IP_TAILSCALE>:19999

7. bash 03-cloudflare-update-ufw.sh
   → Ativa modo Cloudflare-Only
   → Confirmar com 's'

8. bash _audit.sh
   → Validar score (esperado: ~97%)

9. Manutenção futura:
   - Atualizar IPs Cloudflare: bash 03-cloudflare-update-ufw.sh
   - Health check: bash _audit.sh
   - Nova VPS: git pull && repetir passos 4-8
```
