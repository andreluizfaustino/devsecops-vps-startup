# Documentação Técnica — VPS Ubuntu Setup + Hardening

**Autor:** @andreluizfaustino
**Repositório:** https://github.com/andreluizfaustino/devsecops-vps-startup

## Índice

- [Arquitetura](#arquitetura)
- [01-startup.sh](#01-startupsh)
  - [Perguntas iniciais](#perguntas-iniciais)
  - [As 13 fases](#as-13-fases)
  - [Checkpoint, erros e logs](#checkpoint-erros-e-logs)
- [Firewall: UFW, DOCKER-USER e Cloudflare](#firewall-ufw-docker-user-e-cloudflare)
- [_audit.sh](#_auditsh)
- [Arquivos e serviços criados](#arquivos-e-serviços-criados)
- [Decisões de projeto](#decisões-de-projeto)
- [Recuperação de acesso](#recuperação-de-acesso)

---

## Arquitetura

```
Internet
  │
  ├── 80/443  ──► UFW (INPUT, serviços do host)
  │              DOCKER-USER (FORWARD, containers)
  │              aceitam só IPs da Cloudflare (modo Cloudflare-only)
  │
  ├── outras portas ──► bloqueadas (UFW e DOCKER-USER)
  └── SSH ──► não escuta no IP público

Tailscale (100.64.0.0/10)
  └── tudo liberado (SSH, painéis, bancos)
```

Por que duas camadas de firewall:

| Camada | Protege | Por quê |
|---|---|---|
| UFW (chain INPUT) | Serviços do host (SSH, apps fora do Docker) | Firewall padrão do Ubuntu |
| DOCKER-USER (chain FORWARD) | Containers | Portas publicadas pelo Docker passam pela FORWARD, que o UFW não filtra |

---

## 01-startup.sh

Roda uma vez, como root, numa VPS recém-criada (Ubuntu 24.04 ou 26.04 LTS).

```bash
bash 01-startup.sh
```

### Perguntas iniciais

| # | Pergunta | Observações |
|---|---|---|
| 1 | Usuário SSH | `ubuntu` (padrão) ou nome customizado. `root` não é aceito. |
| 2 | Senha do usuário | Mínimo 12 caracteres. Serve para `sudo` e console web — **não** para SSH. Nunca é gravada em disco. |
| 3 | SWAP | Detecta CPU/RAM/disco e sugere: ≤2 GB RAM → 2× RAM; ≤32 GB → 4 GB; >32 GB → 8 GB. Teto: 10% do disco livre. |
| 4 | Chave pública SSH | Validada com `ssh-keygen -l`. |
| 5 | Tailscale / Cloudflare / Docker | Auth key opcional (vazio = login pelo navegador); 80/443 só Cloudflare (padrão S); instalar Docker (padrão S). |

A porta SSH é fixa em 22: o SSH só escuta no Tailscale, então trocar a porta não agrega segurança.

### As 13 fases

| # | Fase | O que faz |
|---|---|---|
| 1 | Usuário | Cria o usuário no grupo `sudo` e define a senha. |
| 2 | Timezone | `America/Sao_Paulo` + NTP. |
| 3 | Atualizar sistema | Desativa o repositório Monarx (Hostinger) se existir; `full-upgrade`; instala curl, ufw, iptables. |
| 4 | Atualizações automáticas | `unattended-upgrades` só com repositórios de **segurança**. Nunca reinicia sozinho; o login mostra `*** System restart required ***` quando precisar. |
| 5 | Sysctl | Ver [tabela abaixo](#sysctl). Limites de 1M file descriptors e core dump desligado. |
| 6 | Módulos do kernel | Bloqueia dccp, sctp, rds, tipc, cramfs, freevxfs, jffs2, hfs, hfsplus, udf (CIS). |
| 7 | SWAP | Remove swaps antigos, cria `/swap/swapfile` com `fallocate`. |
| 8 | Chave SSH | Grava a chave em `~/.ssh/authorized_keys` do usuário. |
| 9 | Tailscale | Instala, conecta (navegador ou auth key) e **exige confirmar** que a expiração da chave foi desativada no painel. |
| 10 | SSH | Grava `/etc/ssh/sshd_config.d/00-hardening.conf`, valida com `sshd -T`, reinicia via `ssh.socket` e **pede para você testar o login em outro terminal**. Se não confirmar, desfaz tudo. |
| 11 | Firewall | UFW: bloqueia entrada, libera Tailscale e 80/443 (Cloudflare ou público). Instala o atualizador semanal dos IPs da Cloudflare. |
| 12 | Docker *(opcional)* | Repositório oficial, `daemon.json` seguro e firewall DOCKER-USER persistente. |
| 13 | Logs | journald persistente, máx. 500 MB / 3 meses. |

Ao final grava `/root/server-info.txt` e pergunta se pode reiniciar.

#### SSH

Configuração efetiva (arquivo `00-hardening.conf`, lido antes de qualquer outro):

- `ListenAddress` só em `127.0.0.1` e nos IPs do Tailscale; `Port 22`
- `PermitRootLogin no`, `AllowUsers <usuário>`, `AuthenticationMethods publickey`
- `PasswordAuthentication no`, `KbdInteractiveAuthentication no`
- `MaxAuthTries 3`, `LoginGraceTime 30`, `MaxSessions 10`
- `KexAlgorithms` montado a partir do que o OpenSSH suporta: `mlkem768x25519-sha256` (OpenSSH 10, pós-quântico), `sntrup761x25519-sha512`, `curve25519-sha256`
- Apenas host key ed25519; ciphers AEAD (chacha20, aes-gcm); MACs etm

Outros arquivos em `sshd_config.d/` (cloud-init, imagem da VPS) são renomeados para `.disabled`.
Backup completo em `/root/ssh-backup-<data>/`.

No Ubuntu 24.04+ o SSH usa *socket activation*: o `ssh.socket` é gerado a partir de `ListenAddress`/`Port`
(com `FreeBind=yes`, então funciona mesmo se o Tailscale subir depois do SSH no boot). Por isso o script faz
`systemctl daemon-reload && systemctl restart ssh.socket`.

#### Sysctl

Arquivo `/etc/sysctl.d/90-hardening.conf` (+ `91-conntrack.conf`):

| Grupo | Parâmetros |
|---|---|
| Kernel | `kernel.dmesg_restrict=1`, `kernel.kptr_restrict=2`, `fs.suid_dumpable=0` |
| Anti-spoofing / redirects | `rp_filter=1`, `accept_redirects=0`, `secure_redirects=0`, `send_redirects=0`, `accept_source_route=0` (IPv4 e IPv6) |
| SYN flood | `tcp_syncookies=1`, `tcp_synack_retries=2`, `tcp_rfc1337=1` |
| Desempenho | `somaxconn=4096`, `tcp_max_syn_backlog=8192`, buffers 16 MB, `tcp_tw_reuse=1`, `tcp_fin_timeout=15`, `tcp_fastopen=3`, `ip_local_port_range=10240 65535`, BBR + fq |
| Arquivos / memória | `fs.file-max=2097152`, `inotify.max_user_watches=524288`, `inotify.max_user_instances=1024`, `vm.swappiness=10` |
| Conntrack | `nf_conntrack_max=1048576`, timeouts curtos (syn_recv/time_wait 15 s) |

**Intencionalmente fora:** `net.ipv4.ip_forward` (Docker e Tailscale precisam de `1`) e `tcp_timestamps=0` (anularia o `tcp_tw_reuse`).

### Checkpoint, erros e logs

- Cada fase concluída é gravada em `.startup-checkpoint`. Rodar de novo oferece **continuar de onde parou**.
- A configuração para retomar fica em `.startup-config` (permissão 600, valores escapados com `printf %q`). Senha e auth key **não** são gravadas: se a fase do usuário ainda não rodou, a senha é pedida de novo.
- `set -Eeuo pipefail` + `trap ERR`: qualquer comando que falhar para o script e mostra linha e comando.
- Logs em `Ubuntu/logs/startup-<data>.log` e `startup-errors.log`.
- Checkpoint e configuração são apagados ao final.

---

## Firewall: UFW, DOCKER-USER e Cloudflare

### Cloudflare-only

`/usr/local/bin/cloudflare-update-firewall.sh`:

1. Baixa `https://www.cloudflare.com/ips-v4` e `ips-v6`.
2. Valida: só aceita linhas no formato CIDR e exige pelo menos 5 faixas IPv4 e 3 IPv6. Lista suspeita → **nada é alterado**.
3. Se a lista mudou (ou com `--force`): remove regras públicas de 80/443, remove faixas que saíram, adiciona as atuais com comentário `Cloudflare`.
4. Grava a lista em `/etc/cloudflare-ips.txt` e reaplica o DOCKER-USER.

Roda toda semana pelo `cloudflare-update-firewall.timer`. Manual: `sudo cloudflare-update-firewall.sh --force`.

### DOCKER-USER

`/usr/local/bin/docker-user-firewall.sh` (serviço `docker-user-firewall`, roda no boot e sempre que o Docker reinicia):

```
1. ESTABLISHED,RELATED            → ACCEPT
2. entrada por tailscale0         → ACCEPT
3. interface pública, porta original 80/443
   de IP da Cloudflare (ou de todos, sem a lista) → ACCEPT
4. interface pública              → DROP
5. resto (tráfego entre containers) → RETURN
```

- A interface pública é detectada pela rota default (não fica fixa em `eth0`).
- As regras usam `-m conntrack --ctorigdstport`, que é a porta **publicada no host**. `--dport` veria a porta interna do container depois do DNAT: um `8080:80` passaria e um `80:3000` seria bloqueado.
- Aplicado em `iptables` e `ip6tables`.

### daemon.json

```json
{
  "ip": "127.0.0.1",
  "no-new-privileges": true,
  "live-restore": true,
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
```

| Opção | Efeito |
|---|---|
| `ip: 127.0.0.1` | `-p 9443:9443` escuta só no localhost. Para expor, diga o IP: `0.0.0.0:443:443` (Traefik) ou `100.x.x.x:9443:9443` (painel via Tailscale). |
| `no-new-privileges` | Processos no container não ganham privilégio via setuid. Imagens que dependem de `sudo` interno podem precisar de `security_opt: ["no-new-privileges=false"]`. |
| `live-restore` | Containers continuam rodando quando o daemon do Docker atualiza/reinicia. |
| log-opts | Máximo 30 MB de log por container. |

O usuário SSH **não** é adicionado ao grupo `docker` (equivale a root sem senha). Use `sudo docker ...`.

---

## _audit.sh

Somente leitura. Rode após o reboot e periodicamente:

```bash
sudo bash _audit.sh
```

| Seção | Verifica |
|---|---|
| Sistema | Versão do Ubuntu, timezone, NTP, swap, unattended-upgrades, reboot automático desligado, **reboot pendente** |
| Sysctl | Todos os parâmetros da tabela, `ip_forward` não fixado em 0, `tcp_timestamps` ligado, BBR, conntrack, file descriptors |
| Módulos | Os 10 módulos bloqueados |
| SSH | Configuração **efetiva** (`sshd -T`): senha off, root off, AllowUsers, escuta só em IPs específicos, Kex pós-quântico, overrides em `sshd_config.d`, Fail2Ban com ban permanente |
| Tailscale | Instalado, conectado, **expiração da chave desativada** |
| UFW | Ativo, deny padrão, IPv6, Tailscale liberado, nada além de 80/443, modo Cloudflare e timer |
| Docker | `daemon.json` (bind, no-new-privileges, live-restore, logs), API não exposta, backend nftables |
| DOCKER-USER | Serviço ativo, DROP na interface pública, uso de `ctorigdstport`, regras Cloudflare, IPv6, containers publicando em `0.0.0.0` |
| Logs | journald com limite e persistente |
| Exposição | SSH no IP público, serviços do host escutando em todos os IPs |

Saída: PASS / FAIL / WARN por item, score e log em `Ubuntu/logs/audit-<data>.log`. Código de saída 1 se houver FAIL.

---

## Arquivos e serviços criados

| Arquivo | Conteúdo |
|---|---|
| `/etc/ssh/sshd_config.d/00-hardening.conf` | Configuração SSH |
| `/root/ssh-backup-<data>/` | Backup do SSH antes da mudança |
| `/etc/sysctl.d/90-hardening.conf`, `91-conntrack.conf` | Kernel e rede |
| `/etc/security/limits.d/90-hardening.conf` | nofile e core dump |
| `/etc/systemd/system.conf.d/90-nofile.conf` | `DefaultLimitNOFILE` |
| `/etc/modules-load.d/tcp_bbr.conf`, `nf_conntrack.conf` | Módulos carregados no boot |
| `/etc/modprobe.d/blacklist-hardening.conf` | Módulos bloqueados |
| `/etc/apt/apt.conf.d/52unattended-upgrades-hardening`, `20auto-upgrades` | Atualizações automáticas |
| `/swap/swapfile` | SWAP |
| `/etc/systemd/journald.conf.d/90-hardening.conf` | Logs |
| `/etc/cloudflare-ips.txt` | Faixas Cloudflare aplicadas |
| `/usr/local/bin/cloudflare-update-firewall.sh` | Atualizador Cloudflare |
| `/usr/local/bin/docker-user-firewall.sh` | Regras DOCKER-USER |
| `/etc/docker/daemon.json` | Configuração do Docker |
| `/root/server-info.txt` | Resumo final |

| Serviço systemd | Quando roda |
|---|---|
| `docker-user-firewall.service` | Boot e todo restart do Docker (`PartOf=docker.service`) |
| `cloudflare-update-firewall.service` | Chamado pelo timer |
| `cloudflare-update-firewall.timer` | Semanal (com atraso aleatório de até 6 h) |

---

## Decisões de projeto

| Decisão | Motivo |
|---|---|
| Sem login root via SSH | Usuário nomeado + sudo deixa rastro de quem fez o quê e exige senha para privilégio. |
| Porta SSH 22 | O SSH não existe no IP público; porta alternativa não protege nada dentro da VPN. |
| Sem Fail2Ban | Só dispositivos do Tailscale alcançam o SSH. O Fail2Ban só poderia banir o próprio administrador (a versão antiga usava ban permanente). |
| Sem auditd | Os logins e o uso de `sudo` já ficam no journald. Auditd só compensa com exigência de compliance (PCI, ISO, SOC2) e alguém revisando. |
| Sem reboot automático | O servidor nunca reinicia sozinho; o aviso aparece no login e no `_audit.sh`. |
| Observabilidade fora do script | Grafana/Loki/Alloy são aplicações: sobem como stack no Portainer, versionadas em Git. O script só garante journald persistente e rotação de logs do Docker. |

---

## Recuperação de acesso

Se o Tailscale cair ou a chave expirar, o SSH fica inacessível. Para entrar:

1. Painel da Hostinger → VPS → **Console / Terminal do navegador**.
2. Login com o usuário (`ubuntu`) e a **senha definida no script**.
3. `sudo tailscale up` (e desative a expiração da chave no painel do Tailscale).

Último recurso: reinstalar o SO pelo painel e rodar o `01-startup.sh` de novo.
