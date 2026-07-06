# 🛡️ VPS Hardening Scripts

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-orange?logo=ubuntu)](https://ubuntu.com/)
[![Bash](https://img.shields.io/badge/Bash-5.0+-green?logo=gnu-bash)](https://www.gnu.org/software/bash/)
[![Tailscale](https://img.shields.io/badge/Tailscale-VPN-blue?logo=tailscale)](https://tailscale.com/)
[![Cloudflare](https://img.shields.io/badge/Cloudflare-Ready-orange?logo=cloudflare)](https://cloudflare.com/)

Conjunto de scripts para hardening, monitoramento e manutenção de servidores Ubuntu em produção.

> 📖 **Documentação técnica completa:** [DOCS.md](DOCS.md)

---

## Scripts

| Script | Quando rodar | O que faz |
|---|---|---|
| `01-startup.sh` | Uma vez, ao provisionar a VPS | Hardening: SSH, firewall, kernel, Tailscale, Fail2Ban, Auditd |
| `02-docker-and-netdata.sh` | Após o reboot do 01 | Instala Docker + Netdata com integrações Fail2Ban e métricas |
| `03-cloudflare-update-ufw.sh` | Após o 01, e quando quiser atualizar | Restringe 80/443 aos IPs oficiais da Cloudflare |
| `04-traefik-and-portainer.sh` | Após o 02 e 03 | Instala Traefik v3 + Portainer CE com Let's Encrypt automático |
| `_audit.sh` | A qualquer momento | Valida todas as configurações e gera score de saúde |

---

## Uso Rápido

```bash
# 1. Clonar o repositório na VPS
git clone https://github.com/andreluizfaustino/devsecops-vps-startup.git
cd devsecops-vps-startup/Ubuntu

# 2. Hardening principal (reboot automático ao final)
bash 01-startup.sh

# 3. Reconectar via Tailscale e instalar Docker + Netdata
bash 02-docker-and-netdata.sh

# 4. Ativar modo Cloudflare-Only
bash 03-cloudflare-update-ufw.sh

# 5. Instalar Traefik + Portainer
bash 04-traefik-and-portainer.sh

# 6. Validar tudo
bash _audit.sh
```

**Score esperado após 01+02+03:** ~97% — 0 FAILs

---

## Arquitetura de Segurança

```
Internet → Cloudflare WAF → UFW (só IPs Cloudflare) → Traefik → Aplicação
Admin    → Tailscale VPN  → SSH (só IP Tailscale)
```

---

## Pré-requisitos

- Ubuntu 22.04 LTS ou 24.04 LTS
- Acesso root
- Conta no [Tailscale](https://tailscale.com) (gratuita)
- Par de chaves SSH (`ssh-keygen -t ed25519`)

---

## Documentação

Para detalhes completos de cada fase, parâmetro e decisão técnica, consulte [DOCS.md](DOCS.md).

---

## Licença

MIT — veja [LICENSE](../LICENSE) para detalhes.

**Autor:** André Luiz Faustino · [@andreluizfaustino](https://github.com/andreluizfaustino)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-orange?logo=ubuntu)](https://ubuntu.com/)
[![Bash](https://img.shields.io/badge/Bash-5.0+-green?logo=gnu-bash)](https://www.gnu.org/software/bash/)
[![Tailscale](https://img.shields.io/badge/Tailscale-VPN-blue?logo=tailscale)](https://tailscale.com/)
[![Cloudflare](https://img.shields.io/badge/Cloudflare-Ready-orange?logo=cloudflare)](https://cloudflare.com/)

Script automatizado de hardening para servidores Ubuntu VPS com **20 fases de segurança**, integração com **Tailscale VPN**, modo **Cloudflare-Only** e sistema de checkpoint para retomar execução em caso de falha.

**🎯 Economia: 85-90% do tempo vs. configuração manual**  
**⏱️ Tempo de execução: ~20-30 minutos**

---

## 📋 Índice

- [Arquitetura de Segurança](#-arquitetura-de-segurança)
- [Features](#-features)
- [Para Quem é Este Script](#-para-quem-é-este-script)
- [Pré-requisitos](#-pré-requisitos)
- [Instalação Rápida](#-instalação-rápida)
- [As 20 Fases de Hardening](#-as-20-fases-de-hardening)
- [Componentes Opcionais](#-componentes-opcionais)
- [Modo Cloudflare-Only](#-modo-cloudflare-only)
- [Exemplos de Uso](#-exemplos-de-uso)
- [Providers Testados](#-providers-testados)
- [Troubleshooting](#-troubleshooting)
- [FAQ](#-faq)
- [Contribuindo](#-contribuindo)
- [Licença](#-licença)
- [Contato](#-contato)

---

## 🏗️ Arquitetura de Segurança

```
Internet
    │
    ▼
┌─────────────────────────────────┐
│         Cloudflare              │  • DDoS protection
│   (proxy + WAF + CDN)           │  • Bot mitigation
│                                 │  • TLS termination
└──────────────┬──────────────────┘
               │ HTTPS (apenas IPs Cloudflare)
               ▼
┌─────────────────────────────────┐
│          UFW Firewall           │  • 80/443: apenas IPs Cloudflare
│       (porta 80 e 443)          │  • Resto: apenas via Tailscale
│                                 │  • Logging medium
└──────────────┬──────────────────┘
               │
               ▼
┌─────────────────────────────────┐
│         Kernel Linux            │  • Conntrack (1M conexões)
│    (network hardening)          │  • SYN cookies + tcp_rfc1337
│                                 │  • ICMP rate limit
└──────────────┬──────────────────┘
               │
               ▼
┌─────────────────────────────────┐
│    CrowdSec + Fail2Ban          │  • CrowdSec: HTTP/bots/scanners
│    (IDS/IPS)                    │  • Fail2Ban: SSH brute force
└──────────────┬──────────────────┘
               │
               ▼
┌─────────────────────────────────┐
│       Suas Aplicações           │  • Docker containers
│    (Docker + Traefik)           │  • Portainer / Coolify
└─────────────────────────────────┘

Admin Access:
    Tailscale VPN → SSH (porta customizada, apenas IP Tailscale)
    Tailscale VPN → Netdata :19999 (monitoramento)
```

---

## 🚀 Features

### Segurança — Rede e Kernel
- ✅ **Modo Cloudflare-Only** — HTTP/HTTPS aceitos APENAS dos IPs da Cloudflare
- ✅ **Cloudflare IP Updater** — Serviço semanal que atualiza ranges automaticamente
- ✅ **UFW com IPv4 + IPv6** — Firewall com logging medium, política DENY por padrão
- ✅ **Conntrack hardening** — Tabela de 1M conexões, timeouts reduzidos (anti-DDoS)
- ✅ **SYN Flood protection** — SYN cookies, tcp_rfc1337, synack_retries=2
- ✅ **Anti-spoofing** — Reverse Path Filter (compatível com Docker/Tailscale)
- ✅ **ICMP Rate Limit** — Limita flood ICMP a 100 pacotes/4s
- ✅ **Kernel Hardening** — ASLR, ptrace restrito, core dumps desabilitados

### Segurança — Acesso
- ✅ **SSH via Tailscale VPN apenas** — Zero exposição pública do SSH
- ✅ **Fail2Ban** — Proteção brute-force (escopo: SSH via Tailscale)
- ✅ **CrowdSec** — IPS colaborativo: bots, scanners, IPs maliciosos, Tor (escopo: HTTP)
- ✅ **Bloqueio de módulos de kernel** — Desabilita dccp, sctp, rds, tipc e filesystems não usados
- ✅ **Auditd** — Monitora acessos a arquivos críticos (otimizado, ~1% overhead)
- ✅ **Criptografia forte** — Ed25519, ChaCha20-Poly1305, curve25519

### Performance
- ⚡ **BBR Congestion Control** — 2-25x mais throughput
- ⚡ **TCP Tuning** — Buffers 16MB, connection queue 4096, TCP Fast Open
- ⚡ **1M File Descriptors** — Suporta APIs de alto tráfego
- ⚡ **SWAP configurável** — Criado e persistido automaticamente

### Infraestrutura
- 🐳 **Docker Engine** — Instalação via script oficial, usuário adicionado ao grupo
- 📊 **Netdata** — Monitoramento completo: host + Docker + Traefik em 1 container, UI via Tailscale:19999

### Automação
- 🔄 **Sistema de Checkpoint** — Pause e continue de onde parou em caso de falha
- 📊 **Logging Completo** — Todos os comandos com timestamp
- 📈 **Progress Bar Visual** — Acompanhe o progresso em tempo real
- 🤝 **Configuração Interativa** — Guiado passo a passo

---

## 👥 Para Quem é Este Script

- **Desenvolvedores** que gerenciam suas próprias VPS
- **Product Builders** criando ambientes rapidamente
- **Empreendedores** sem time de DevOps dedicado
- **Freelancers** mantendo múltiplos servidores
- **Equipes pequenas** sem budget para ferramentas enterprise

Especialmente útil para quem usa **Cloudflare + Docker + Traefik** e quer proteção em camadas desde o SO.

---

## 📦 Pré-requisitos

### No Servidor (VPS)
- Ubuntu 22.04 LTS ou 24.04 LTS
- Acesso root via console (web ou SSH)
- Mínimo 1GB RAM (recomendado 2GB+)
- Conexão com internet

### No Seu Computador Local
- Conta no [Tailscale](https://tailscale.com) (gratuita para até 20 dispositivos)
- Par de chaves SSH (`ssh-keygen -t ed25519`)
- Cliente Tailscale instalado

### Se usar Modo Cloudflare-Only
- Domínios com proxy Cloudflare ativo (nuvem laranja) — **obrigatório**
- Sem proxy ativo, o site ficará inacessível

---

## ⚡ Instalação Rápida

### 1. Conectar ao Servidor

```bash
# Via SSH temporário ou console web do provider
ssh root@SEU_IP_PUBLICO
```

### 2. Baixar o Script

```bash
git clone https://github.com/andreluizfaustino/devsecops-vps-startup.git
cd devsecops-vps-startup/Ubuntu
chmod +x startup.sh
```

### 3. Preparar Chave SSH

**No seu computador local:**

```bash
# Gerar chave (se não tiver)
ssh-keygen -t ed25519 -C "seu-email@example.com"

# Copiar chave pública
cat ~/.ssh/id_ed25519.pub
# macOS:
cat ~/.ssh/id_ed25519.pub | pbcopy
```

### 4. Executar o Script

```bash
sudo bash startup.sh
```

### 5. Seguir o Assistente Interativo

O script pedirá:
- Usuário SSH (root/ubuntu/customizado)
- Senha do usuário
- Porta SSH (padrão: 2222)
- Tamanho do SWAP (padrão: 2GB)
- Chave SSH pública
- Componentes opcionais

### 6. Autenticar no Tailscale

Durante a **Fase 9**, o script exibirá uma URL:

```
⚠️  AÇÃO NECESSÁRIA: Autenticação Tailscale

Abra este link no navegador:
https://login.tailscale.com/a/xxxxxxxxxxxxxxxx
```

1. Abra o link no navegador
2. Faça login na conta Tailscale
3. Autorize o dispositivo
4. Pressione ENTER no terminal

### 7. Acessar via SSH Seguro

```bash
# Conecte ao Tailscale no seu computador
tailscale up

# Acesse via IP Tailscale
ssh ubuntu@100.64.x.x -p 2222
```

✅ **Pronto!** Servidor seguro e pronto para produção.

---

## 🔐 As 20 Fases de Hardening

### Fases Obrigatórias

| Fase | Nome | O Que Faz | Tempo |
|------|------|-----------|-------|
| **1** | Usuário SSH | Cria/configura usuário com sudo | ~10s |
| **2** | Timezone | America/Sao_Paulo + NTP | ~5s |
| **3** | System Update | `apt update && upgrade` + limpeza | ~3-5min |
| **5** | Kernel Security | ASLR, ptrace, core dumps | ~10s |
| **6** | Network Hardening | SYN cookies, conntrack, BBR, rp_filter, ICMP rate limit, 1M fds | ~30s |
| **7** | SWAP | Cria swapfile no tamanho configurado | ~1-2min |
| **8** | Chave SSH | Configura authorized_keys | ~5s |
| **9** | **Tailscale** | Instala e conecta VPN ⚠️ *ação manual* | ~2-3min |
| **10** | **SSH Hardening** | SSH apenas no IP Tailscale, criptografia forte | ~30s |
| **11** | Fail2Ban | Brute-force SSH | ~1min |
| **12** | **UFW Firewall** | Logging medium, DENY padrão, regras Cloudflare ou público | ~30s |

### Fases Opcionais

| Fase | Nome | Padrão | O Que Faz | Tempo |
|------|------|--------|-----------|-------|
| **4** | Unattended Upgrades | **S** | Patches de segurança automáticos | ~2min |
| **13** | Cloudflare IP Updater | *(auto se CF-Only=S)* | Timer semanal, atualiza ranges CF no UFW | ~30s |
| **14** | CrowdSec | **S** | IPS colaborativo: bots, scanners, reputação | ~3min |
| **15** | Kernel Modules | **S** | Bloqueia protocolos e filesystems não usados | ~5s |
| **16** | Auditd | **S** | Monitora /etc/passwd, sudo, sshd_config | ~2min |
| **17** | Logging Avançado | **S** | Logrotate + journald 500MB | ~5s |
| **18** | Docker Engine | **S** | Instala via get.docker.com | ~3min |
| **19** | Netdata | **S** *(se Docker=S)* | Monitoramento host + Docker + Traefik | ~2min |

---

## 🎛️ Configuração Interativa

```
════════════════════════════════════════════════════════
  CONFIGURAÇÃO INICIAL DO SISTEMA
════════════════════════════════════════════════════════

ETAPA 1/5: Configurar usuário SSH
  1) root
  2) ubuntu ✅ (recomendado)
  3) outro
Opção [1-3]: 2

ETAPA 2/5: Definir senha para usuário ubuntu
Digite a nova senha: ********

ETAPA 3/5: Configurar porta SSH [padrão: 2222]: 2222

ETAPA 4/5: Configurar SWAP em GB [padrão: 2]: 4

ETAPA 5/5: Cole sua chave pública SSH: ssh-ed25519 AAAAC3Nz...

════════════════════════════════════════════════════════
  COMPONENTES OPCIONAIS DE SEGURANÇA
════════════════════════════════════════════════════════

[1] Unattended Upgrades    Instalar? [S/n]: S
[2] Auditd                 Instalar? [S/n]: S
[4] Logging Avançado       Instalar? [S/n]: S
[5] Modo Cloudflare-Only   Ativar?   [S/n]: S
[6] CrowdSec               Instalar? [S/n]: S
[7] Bloqueio Módulos Kernel Instalar? [S/n]: S
[8] Docker                 Instalar? [S/n]: S
[8b] Netdata               Instalar? [S/n]: S

Resumo:
  ✅ Unattended Upgrades
  ✅ Auditd
  ✅ Logging Avançado
  ✅ Modo Cloudflare-Only
  ✅ CrowdSec
  ✅ Bloqueio de Módulos de Kernel
  ✅ Docker Engine
  ✅ Netdata (monitoramento completo)
```

---

## 🧩 Componentes Opcionais

### [1] Unattended Upgrades
Instala patches de segurança do Ubuntu automaticamente. Apenas updates de segurança — não atualiza pacotes que possam quebrar aplicações. Reboot manual necessário se o kernel for atualizado.

### [2] Auditd
Monitora e registra acessos a arquivos críticos:
- `/etc/passwd`, `/etc/shadow` — alterações
- `/etc/ssh/sshd_config` — alterações
- `/usr/bin/sudo`, `/bin/su` — execuções

Configurado com overhead mínimo (~1%). Logs em `/var/log/audit/`.

### [4] Logging Avançado
Configura rotação de logs e limita journald a 500MB para evitar disco cheio.

### [5] Modo Cloudflare-Only ⭐
Restringe as portas 80 e 443 exclusivamente aos ranges IPv4 e IPv6 oficiais da Cloudflare. Qualquer scanner, bot ou ataque direto ao IP público é dropado silenciosamente.

**Requer:** todos os domínios com proxy Cloudflare ativo (nuvem laranja).

Ranges aplicados: 15 IPv4 + 7 IPv6 (fonte: cloudflare.com/ips).

### [5b] Cloudflare IP Updater *(ativado automaticamente com CF-Only)*
Serviço systemd que executa semanalmente:
1. Busca os ranges atuais em `cloudflare.com/ips-v4` e `cloudflare.com/ips-v6`
2. Remove as regras antigas do UFW
3. Adiciona os novos ranges

```bash
# Executar manualmente
systemctl start cf-update-ufw.service

# Ver log
cat /var/log/cf-update-ufw.log

# Próxima execução
systemctl status cf-update-ufw.timer
```

### [6] CrowdSec
IPS colaborativo de código aberto. Aprende com ataques em servidores do mundo inteiro.

- **Bouncer iptables**: bloqueia IPs maliciosos em tempo real
- **Collections**: linux, traefik, nginx
- **Escopo distinto do Fail2Ban**: CrowdSec → HTTP/bots; Fail2Ban → SSH

```bash
cscli decisions list   # IPs bloqueados
cscli alerts list      # Alertas recentes
cscli metrics          # Estatísticas
cscli hub update       # Atualizar threat intelligence
```

### [7] Bloqueio de Módulos de Kernel
Desabilita módulos desnecessários em servidores (CIS Benchmark):
- **Protocolos**: `dccp`, `sctp`, `rds`, `tipc`
- **Filesystems**: `cramfs`, `freevxfs`, `jffs2`, `hfs`, `hfsplus`, `udf`

### [8] Docker Engine
Instala via `get.docker.com`, habilita serviço, adiciona usuário SSH ao grupo `docker`.

### [8b] Netdata *(requer Docker)*
Monitoramento completo em 1 container:

| Cobertura | Como |
|-----------|------|
| Host (CPU, RAM, disco, rede, processos) | Via `/proc` e `/sys` |
| Docker containers | Via `docker.sock` |
| Traefik | Integração nativa automática |

**Acesso:** `http://<IP_Tailscale>:19999` — protegido pelo UFW, apenas via Tailscale.

```bash
cd /opt/netdata
docker compose ps
docker compose logs
docker compose restart
```

---

## ☁️ Modo Cloudflare-Only

### Como funciona

```
Usuário  → cloudflare.com → proxy CF → SEU_IP:80/443  ✅ permitido
Atacante → SEU_IP:80/443                               ❌ UFW DROP
Scanner  → SEU_IP:80/443                               ❌ UFW DROP
```

### Checklist antes de ativar

- [ ] Todos os domínios com nuvem **laranja** (proxy ativo) na Cloudflare
- [ ] Nenhum domínio com nuvem cinza (acesso direto ao IP)
- [ ] Acesso ao servidor via Tailscale garantido

### Manutenção automática dos IPs

```bash
# Ver última atualização
cat /var/log/cf-update-ufw.log | tail -5

# Forçar atualização agora
sudo systemctl start cf-update-ufw.service
```

---

## 💡 Exemplos de Uso

### VPS com Coolify

```bash
# 1. Execute o script (com Docker=S)
sudo bash startup.sh

# 2. Instale Coolify (Docker já instalado)
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash

# 3. Acesse via Tailscale
# http://<IP_Tailscale>:8000
```

> O Coolify gerencia seu próprio Traefik — não instale Traefik separado.

### VPS com Portainer

```bash
# 1. Execute o script (com Docker=S)
sudo bash startup.sh

# 2. Suba o Portainer
docker volume create portainer_data
docker run -d \
  --name portainer --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  -p 9000:9000 \
  portainer/portainer-ce:latest

# 3. Acesse via Tailscale
# http://<IP_Tailscale>:9000
```

### Múltiplos Servidores

```bash
# Todos na mesma rede Tailscale
ssh ubuntu@100.64.1.10 -p 2222  # Produção
ssh ubuntu@100.64.1.11 -p 2222  # Staging
```

---

## ☁️ Providers Testados

| Provider | Status | Notas |
|----------|--------|-------|
| **Hostinger** | ✅ Testado | Funciona perfeitamente |
| **DigitalOcean** | ✅ Testado | Funciona perfeitamente |
| **Hetzner** | ✅ Testado | Funciona perfeitamente |
| **Vultr** | ✅ Testado | Funciona perfeitamente |
| **Linode/Akamai** | ✅ Testado | Funciona perfeitamente |
| **AWS Lightsail** | ⚠️ Não testado | Deve funcionar |
| **GCP Compute** | ⚠️ Não testado | Deve funcionar |
| **Azure VMs** | ⚠️ Não testado | Deve funcionar |

---

## 🔧 Troubleshooting

### ❌ Perdi o acesso SSH

```bash
# Reconectar Tailscale localmente
tailscale up
tailscale status
ssh ubuntu@100.64.x.x -p 2222
```

**Plano B:** Console web do provider → `sudo tailscale up`.

---

### ❌ Site inacessível após Cloudflare-Only

Domínio com nuvem cinza (sem proxy). No painel Cloudflare, ative a nuvem **laranja** no DNS record. Aguarde ~1 min.

---

### ❌ Script falhou na fase X

```bash
sudo bash startup.sh
# "Checkpoint encontrado! X de 20 fases concluídas."
# Escolha: 1) Continuar de onde parou
```

---

### ❌ Como ver os logs?

```bash
cat logs/startup-YYYYMMDD_HHMMSS.log   # Log completo
cat logs/startup-errors.log             # Apenas erros
cat /root/server-info.txt               # Resumo do servidor
cat /var/log/cf-update-ufw.log          # Cloudflare IP Updater
```

---

### ❌ Preciso abrir uma porta extra

```bash
# Apenas via Tailscale (recomendado)
sudo ufw allow in on tailscale0 to any port 3000

# Publicamente (use com cautela)
sudo ufw allow 3000/tcp comment 'Minha aplicação'

sudo ufw status numbered
```

---

### ❌ Restaurar SSH anterior

```bash
ls /etc/ssh/sshd_config.backup.*
sudo cp /etc/ssh/sshd_config.backup.YYYYMMDD_HHMMSS /etc/ssh/sshd_config
sudo systemctl restart sshd
```

---

### ❌ Netdata não abre

```bash
docker ps | grep netdata
cd /opt/netdata && docker compose logs
docker compose restart
# Acesso: http://<IP_Tailscale>:19999
```

---

## ❓ FAQ

**P: Posso usar em Debian?**  
R: O script foi projetado para Ubuntu. Pode funcionar em Debian com aviso.

**P: Preciso do Tailscale?**  
R: Sim, é obrigatório. O SSH escuta apenas no IP Tailscale.

**P: Ativo Cloudflare-Only sem ter domínios configurados?**  
R: Não. Configure os domínios na Cloudflare com proxy ativo primeiro.

**P: CrowdSec e Fail2Ban conflitam?**  
R: Não. Escopos distintos: Fail2Ban → SSH; CrowdSec → HTTP/bots.

**P: Netdata fica exposto na internet?**  
R: Não. Porta 19999 sem regra UFW pública — apenas Tailscale.

**P: Posso rodar em servidor de produção?**  
R: ⚠️ Não recomendado. Teste em staging primeiro. Sempre tenha acesso ao console web.

**P: Como adicionar outro usuário SSH?**

```bash
sudo useradd -m -s /bin/bash -G sudo novoUsuario
sudo passwd novoUsuario
sudo mkdir -p /home/novoUsuario/.ssh
echo "CHAVE_PUBLICA" | sudo tee /home/novoUsuario/.ssh/authorized_keys
sudo chmod 700 /home/novoUsuario/.ssh
sudo chmod 600 /home/novoUsuario/.ssh/authorized_keys
sudo chown -R novoUsuario:novoUsuario /home/novoUsuario/.ssh
# Adicionar ao AllowUsers no sshd_config
sudo sed -i 's/^AllowUsers .*/& novoUsuario/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

---

## 🤝 Contribuindo

1. Fork o repositório
2. Crie uma branch: `git checkout -b feature/minha-feature`
3. Commit: `git commit -m 'feat: descrição'`
4. Push: `git push origin feature/minha-feature`
5. Abra um Pull Request

**Diretrizes:** Teste em VPS real · Mantenha compatibilidade Ubuntu 22.04/24.04 · [Conventional Commits](https://www.conventionalcommits.org/)

---

## 📜 Licença

**MIT License** — use, copie, modifique e distribua livremente, inclusive para fins comerciais.

---

## ⚠️ Aviso Importante

- ✅ Teste em VPS não-produção primeiro
- ⚠️ Configuração incorreta pode bloquear acesso SSH
- 📋 Tenha acesso ao console web do provider
- 🚫 Fornecido "como está", sem garantias

**Use por sua conta e risco.**

---

## 📞 Contato

**Autor:** André Luiz Faustino  
**GitHub:** [@andreluizfaustino](https://github.com/andreluizfaustino)  
**Repositório:** [devsecops-vps-startup](https://github.com/andreluizfaustino/devsecops-vps-startup)

- 🐛 **Bugs:** [Issues](https://github.com/andreluizfaustino/devsecops-vps-startup/issues)
- 💬 **Discussões:** [Discussions](https://github.com/andreluizfaustino/devsecops-vps-startup/discussions)

---

*Feito com 🛡️ para a comunidade DevSecOps brasileira.*
