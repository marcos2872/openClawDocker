FROM ubuntu:24.04

# Evita prompts interativos durante instalações
ENV DEBIAN_FRONTEND=noninteractive

# Atualiza o sistema e instala pacotes essenciais
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    vim \
    git \
    bash \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Verifica e instala o Node.js 24 via NodeSource (mínimo exigido: 22.14+)
RUN echo "· Node.js not found, installing it now" && \
    echo "· Installing Node.js via NodeSource" && \
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Instala as ferramentas de build do Linux
RUN echo "· Installing Linux build tools (make/g++/cmake/python3)" && \
    apt-get update && apt-get install -y \
    make \
    g++ \
    cmake \
    python3 \
    python3-pip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Instala o pnpm 10 (package manager exigido pelo OpenClaw)
RUN npm install -g pnpm@10

# Instala o OpenClaw globalmente
RUN npm install -g openclaw@latest

# Define o diretório de trabalho
WORKDIR /workspace

# Expõe a porta padrão do OpenClaw Gateway
EXPOSE 18789

# Comando padrão ao iniciar o container
CMD ["/bin/bash"]
