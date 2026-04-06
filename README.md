# 🐳 OpenClaw Docker

Container Ubuntu 24.04 pronto para rodar o [OpenClaw](https://github.com/openclaw/openclaw) — Personal AI Assistant.

---

## 📦 O que está incluído na imagem

| Componente | Versão |
|---|---|
| Ubuntu | 24.04 |
| Node.js | 24.x (mínimo exigido: `>=22.14.0`) |
| pnpm | 10 |
| OpenClaw CLI | latest |
| make / g++ / cmake / python3 | via apt |
| curl / wget / vim / git | via apt |

---

## 📁 Estrutura de arquivos

```
.
├── Dockerfile          # Imagem Ubuntu com Node.js 24 + OpenClaw
├── docker-compose.yml  # Serviço com porta 18789 e volume persistente
├── Makefile            # Atalhos para Docker e Podman
└── README.md
```

---

## ⚙️ Pré-requisitos

Você precisa de **Docker** ou **Podman** instalado:

```bash
# Docker
https://docs.docker.com/engine/install/

# Podman
https://podman.io/docs/installation

# podman-compose (se usar Podman)
pip install podman-compose
# ou
sudo apt install podman-compose
```

> O `Makefile` detecta automaticamente qual engine está disponível. Docker tem prioridade se ambos estiverem instalados.

---

## 🚀 Início rápido

```bash
# 1. Constrói a imagem
make build

# 2. Sobe o container em background
make up

# 3. Entra no container
make shell
```

---

## 🛠️ Comandos disponíveis

```bash
make help       # Lista todos os comandos e o engine detectado
make build      # Constrói a imagem Docker/Podman
make up         # Sobe o container em background
make down       # Para e remove o container
make shell      # Abre bash interativo dentro do container
make logs       # Exibe os logs em tempo real
make restart    # Reinicia o container
make clean      # Remove container, imagem e volumes
make rebuild    # Limpa tudo e reconstrói do zero
```

---

## 🔌 Porta

| Porta | Descrição |
|---|---|
| `18789` | Gateway do OpenClaw (host → container) |

Após subir o container, o gateway estará acessível em:

```
http://localhost:18789
```

---

## 💾 Persistência

Os dados do `/workspace` dentro do container são armazenados em um **volume nomeado** gerenciado pelo Docker/Podman:

```
ubuntu_workspace
```

O volume **não é removido** ao recriar o container (`make rebuild`).  
Para apagar os dados completamente:

```bash
make clean

# ou manualmente:
docker volume rm ubuntu_workspace
podman volume rm ubuntu_workspace
```

---

## 🦞 Usando o OpenClaw

Após entrar no container com `make shell`:

```bash
# Configuração inicial (passo a passo guiado)
openclaw onboard

# Sobe o Gateway na porta exposta
openclaw gateway --port 18789 --bind lan --verbose

# Envia uma mensagem
openclaw message send --to +5511999999999 --message "Olá!"

# Fala com o assistente
openclaw agent --message "Resumo do dia" --thinking high
```

> Consulte a documentação completa em: https://docs.openclaw.ai

---

## 🖥️ Web UI (Control UI)

O OpenClaw possui uma interface web integrada ao gateway, acessível pelo navegador da sua máquina host.

### Configuração inicial (apenas uma vez)

```bash
make shell
```

Dentro do container, rode os comandos abaixo **na ordem**:

```bash
# 1. Configura o gateway (gera token, cria workspace e sessões)
openclaw setup

# 2. Permite que o navegador da máquina host acesse a Control UI
openclaw config set gateway.controlUi.allowedOrigins '["http://localhost:18789","http://127.0.0.1:18789"]'

# 3. Desativa o pairing obrigatório de device no browser
#    Sem isso o browser fica preso em "pairing required" mesmo com token correto
openclaw config set gateway.controlUi.dangerouslyDisableDeviceAuth true

# 4. Sobe o gateway escutando em todas as interfaces (0.0.0.0)
#    Sem --bind lan o gateway escuta só no loopback interno do container
#    e o navegador do host recebe ERR_CONNECTION_RESET
openclaw gateway --port 18789 --bind lan --verbose
```

---

### Acessar no navegador

Abra no navegador da sua máquina host:

```
http://127.0.0.1:18789
```

---

### Obter o token de autenticação

O token é gerado automaticamente ao iniciar o gateway pela primeira vez e salvo no `openclaw.json`:

```bash
# Dentro do container:
node -e "const c=require('/root/.openclaw/openclaw.json'); console.log(c?.gateway?.auth?.token)"
```

Ou obtenha a URL já autenticada diretamente:

```bash
# Dentro do container (com o gateway rodando em outro terminal):
openclaw dashboard --no-open
# Retorna: http://127.0.0.1:18789/#token=<seu-token>
```

Cole o token no campo **Token do Gateway** e clique em **Conectar**.

---

### Resumo dos erros comuns

| Erro | Causa | Solução |
|---|---|---|
| `ERR_CONNECTION_RESET` | Gateway ouvindo só no loopback interno | Usar `--bind lan` |
| `non-loopback Control UI requires...` | Origens não configuradas | `openclaw config set gateway.controlUi.allowedOrigins '[...]'` |
| `pairing required` | Verificação de device ativa | `openclaw config set gateway.controlUi.dangerouslyDisableDeviceAuth true` |

---

### Health checks

A Web UI expõe dois endpoints **sem autenticação** para verificar o status do gateway:

```bash
# Na sua máquina host:
curl -fsS http://127.0.0.1:18789/healthz   # liveness  (está vivo?)
curl -fsS http://127.0.0.1:18789/readyz    # readiness (está pronto?)
```

Health check autenticado com snapshot completo:

```bash
# Dentro do container:
openclaw health --token "$OPENCLAW_GATEWAY_TOKEN"
```

---

### Configurar canais de mensagem

Após autenticar na Web UI, conecte canais diretamente pela interface ou via CLI:

```bash
# WhatsApp (QR code no terminal)
openclaw channels login

# Telegram
openclaw channels add --channel telegram --token "<token>"

# Discord
openclaw channels add --channel discord --token "<token>"

# Slack
openclaw channels add --channel slack --token "<token>"
```

**Canais suportados:** WhatsApp, Telegram, Slack, Discord, Google Chat, Signal, iMessage, BlueBubbles, IRC, Microsoft Teams, Matrix, Feishu, LINE, Mattermost, Nextcloud Talk, Nostr, Synology Chat, Twitch, Zalo, WeChat e mais.

---

## 🤖 Configurar provedor de IA (obrigatório)

Sem uma chave de API configurada o agente falha com:
```
All models failed: No API key found for provider "openai"
```

Escolha um provedor e configure dentro do container:

---

### OpenRouter (recomendado — uma chave para muitos modelos)

O OpenRouter é a opção mais prática: uma única chave de API dá acesso a dezenas de modelos (GPT, Claude, Gemini, Llama, etc.), inclusive com plano gratuito.

```bash
# Opção 1 — Onboarding guiado (recomendado, configura tudo automaticamente):
openclaw onboard --auth-choice openrouter-api-key

# Opção 2 — Variável de ambiente (mais simples):
export OPENROUTER_API_KEY="sk-or-..."
openclaw models set openrouter/auto

# Opção 3 — Config manual (todos os campos de uma vez, obrigatório como objeto JSON):
openclaw config set models.providers.openrouter '{"baseUrl":"https://openrouter.ai/api/v1","apiKey":"sk-or-...","models":[]}'
openclaw models set openrouter/auto
```

Modelos populares via OpenRouter:

```bash
openclaw models set openrouter/openai/gpt-4o
openclaw models set openrouter/anthropic/claude-opus-4-5
openclaw models set openrouter/meta-llama/llama-3.3-70b-instruct
openclaw models set openrouter/openai/gpt-oss-120b:free  # gratuito
```

> Crie sua chave gratuita em: https://openrouter.ai/keys

---

### Ollama (local — sem custo, sem internet)

O Ollama roda modelos de IA localmente na sua máquina. O OpenClaw se conecta a ele via API nativa.

> ⚠️ O Ollama precisa estar instalado e rodando **na sua máquina host**, não dentro do container.

**1. Instale e inicie o Ollama na máquina host:**

```bash
# Instalar
curl -fsSL https://ollama.com/install.sh | sh

# Baixar um modelo
ollama pull llama3.3
# ou
ollama pull qwen2.5-coder:32b
```

**2. Ajuste o docker-compose.yml para expor o Ollama ao container:**

No `docker-compose.yml`, adicione a variável de ambiente:
```yaml
environment:
  - OLLAMA_API_KEY=ollama-local
  - OLLAMA_HOST=http://host-gateway:11434   # acessa o host a partir do container
```

**3. Configure o OpenClaw dentro do container:**

```bash
openclaw config set models.providers.ollama.apiKey "ollama-local"
openclaw config set models.providers.ollama.baseUrl "http://host-gateway:11434"
openclaw models set ollama/llama3.3
```

> ⚠️ **Nunca use `/v1` na URL do Ollama** — isso ativa o modo OpenAI-compatible e quebra o tool calling. Use sempre `http://host:11434` sem sufixo.

Ver modelos disponíveis:

```bash
ollama list              # na máquina host
openclaw models list     # dentro do container
```

---

### OpenAI

```bash
openclaw config set models.providers.openai.apiKey "sk-..."
openclaw models set openai/gpt-4o
```

### Anthropic (Claude)

```bash
openclaw config set models.providers.anthropic.apiKey "sk-ant-..."
openclaw models set anthropic/claude-opus-4-5
```

### Google Gemini

```bash
openclaw config set models.providers.google.apiKey "AIza..."
openclaw models set google/gemini-2.0-flash
```

---

### Verificar autenticação configurada

```bash
openclaw doctor          # mostra provedores autenticados e problemas
openclaw models list     # lista modelos disponíveis
```

> Consulte todos os provedores e modelos em: https://docs.openclaw.ai/concepts/models

---

## 🔄 Atualizar o OpenClaw

```bash
make shell

# Dentro do container:
npm install -g openclaw@latest

# ou para canais específicos:
openclaw update --channel stable   # versão estável
openclaw update --channel beta     # pré-lançamento
openclaw update --channel dev      # última do main
```

---

## 🩺 Diagnóstico

```bash
make shell

# Dentro do container:
openclaw doctor        # verifica configuração e dependências
node --version         # deve ser >= 22.14.0
pnpm --version         # deve ser 10.x
```
