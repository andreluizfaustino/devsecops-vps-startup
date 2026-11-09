# 🛡️ VPS Ubuntu — Setup + Hardening

[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04%20%7C%2026.04-orange?logo=ubuntu)](https://ubuntu.com/)
[![Bash](https://img.shields.io/badge/Bash-5.0+-green?logo=gnu-bash)](https://www.gnu.org/software/bash/)
[![Tailscale](https://img.shields.io/badge/Tailscale-VPN-blue?logo=tailscale)](https://tailscale.com/)
[![Cloudflare](https://img.shields.io/badge/Cloudflare-Ready-orange?logo=cloudflare)](https://cloudflare.com/)

Um script que transforma uma VPS Ubuntu recém-criada em um servidor pronto para produção:
SSH só pelo Tailscale, firewall fechado, Docker que não fura o firewall e atualizações de segurança automáticas.

> 📖 Detalhes técnicos de cada fase: [DOCS.md](DOCS.md)

---

## Scripts

| Script | Quando rodar | O que faz |
|---|---|---|
| `01-startup.sh` | Uma vez, na VPS nova | Configura e protege o servidor (13 fases) |
| `_audit.sh` | Depois do 01 e de tempos em tempos | Confere tudo e dá uma nota (só leitura) |

---

## Rotina para uma VPS nova

**Antes:** tenha o Tailscale instalado no seu computador e um par de chaves SSH (`ssh-keygen -t ed25519`).

```bash
# 1. Entrar na VPS nova com o IP público e a senha de root do painel
ssh root@IP_PUBLICO

# 2. Baixar e rodar
git clone https://github.com/andreluizfaustino/devsecops-vps-startup.git
cd devsecops-vps-startup/Ubuntu
bash 01-startup.sh
```

O script faz 5 perguntas no início (usuário, senha, swap, chave pública, Tailscale/Cloudflare/Docker)
e depois pede sua ação em dois momentos:

1. **Tailscale** — autenticar o servidor (link no navegador ou auth key) e **desativar a expiração da chave** no painel.
2. **Teste do SSH** — em outro terminal, testar `ssh ubuntu@100.x.x.x`. Se não funcionar, o script desfaz a mudança e você não perde o acesso.

No final ele pergunta se pode reiniciar. Depois disso:

```bash
# 3. Entrar pelo IP do Tailscale (o IP público não aceita mais SSH)
ssh ubuntu@100.x.x.x

# 4. Conferir
sudo bash ~/devsecops-vps-startup/Ubuntu/_audit.sh   # ou onde você clonou
```

O IP do Tailscale e o resumo da configuração ficam em `/root/server-info.txt`.

Se algo falhar no meio, corrija e rode `bash 01-startup.sh` de novo: ele continua da fase em que parou.

---

## Arquitetura

```
Internet
  ├── 80/443 ── só IPs da Cloudflare* ──► UFW (host) e DOCKER-USER (containers) ──► Traefik/app
  ├── qualquer outra porta ──────────────► bloqueado
  └── SSH ──────────────────────────────► não existe no IP público

Tailscale (100.x.x.x)
  └── tudo liberado: SSH, Portainer, Grafana, bancos...

* ou de qualquer IP, se você responder "n" ao modo Cloudflare-only
```

**Por que DOCKER-USER?** Portas publicadas pelo Docker passam por uma chain do iptables que o UFW não filtra.
Sem essa proteção, um `-p 9443:9443` fica aberto para a internet mesmo com o UFW bloqueando tudo.

---

## Depois do setup

O script não instala aplicações. A camada seguinte está pronta em **[`../stacks/`](../stacks/README.md)**:

- **Traefik** (+ socket-proxy): certificado de Origem da Cloudflare, IP real do visitante, rate limit, cabeçalhos de segurança e limite de upload aplicados a todas as aplicações.
- **Portainer**: só pelo Tailscale.

Regras para as suas aplicações:
- Públicas: rede `proxy` + labels do Traefik, sem `ports:`.
- Painéis administrativos: publique no IP do Tailscale, ex.: `"100.x.x.x:9443:9443"` (o script já habilita `ip_nonlocal_bind` para isso funcionar no boot).

---

**Autor:** André Luiz Faustino · [@andreluizfaustino](https://github.com/andreluizfaustino)
