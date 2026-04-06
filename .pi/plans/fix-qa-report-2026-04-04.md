# Plano: Correções do Relatório de QA — 2026-04-04

**Data:** 2026-04-04  
**Autor:** agente-plan  
**Status:** aprovado

---

## Objetivo

Corrigir todos os bugs e inconsistências identificados no relatório de QA gerado em 2026-04-04,
priorizando o item de risco ALTO (account takeover) e seguindo a ordem de severidade descendente.
Ao final, nenhum item de risco ALTO ou MÉDIO deve permanecer aberto.

---

## Escopo

**Dentro do escopo:**
- Correção do bug de account takeover no callback GitHub OAuth (ALTO)
- Correção do token Copilot não persistido sem aviso (MÉDIO)
- Correção dos type hints errados de `user_id` / `project_id` em `agent_adapter.py` e `setup_agent.py` (MÉDIO)
- Adição de limite de tamanho de upload em `project_files.py` e `rag_service/main.py` (MÉDIO)
- Propagação de exceções em `SetupAgentService.chat()` em vez de retornar strings de erro (MÉDIO)
- Garantia de que `delete_file_chunks` sempre receba `user_id` (MÉDIO)
- Correção de `_ALLOWED_DOMAIN` para lowercase (BAIXO)
- Substituição de `asyncio.get_event_loop()` por `get_running_loop()` (BAIXO)
- Limpeza de arquivo temporário em `_resolve_pptx_path` (BAIXO)
- Remoção de `return contextlib.nullcontext()` desnecessário em `_on_status` (BAIXO)
- Adição de `is_auth_error` em `invoke_with_callbacks` (BAIXO)
- Ocultação de detalhes de exceção interna nas respostas HTTP (BAIXO)
- Adição de limite de tamanho para `body.content` no chat (BAIXO)

**Fora do escopo:**
- Trocar o KDF de SHA-256 por PBKDF2/HKDF (mudança de infraestrutura com impacto em tokens já persistidos — requer migração de dados)
- Mover `storage_key`/`user_id` de query params para body no DELETE do rag_service (mudança de contrato de API com impacto no adaptador `src/infrastructure/rag_adapter.py`)
- Validar `GITHUB_CLIENT_ID`/`GITHUB_CLIENT_SECRET` em tempo de uso (requer mudança de arquitetura no módulo `github_oauth.py`)
- Escrita de novos testes automatizados (coberto por plano de testes separado — skill `agent-test`)

---

## Arquivos Afetados

| Arquivo | Ação | Motivo |
|---|---|---|
| `backend/routers/auth_github.py` | modificar | Corrigir account takeover no callback OAuth + lowercase do `_ALLOWED_DOMAIN` |
| `backend/routers/auth_copilot.py` | modificar | Emitir erro quando `db_user` for `None` no poll SSE |
| `backend/routers/chat.py` | modificar | Adicionar limite de tamanho para `body.content` |
| `backend/routers/project_files.py` | modificar | Limite de upload + type hint `project_id: str` em `_get_user_project` |
| `backend/routers/pptx.py` | modificar | Limpeza do arquivo temporário em `_resolve_pptx_path` |
| `backend/routers/templates_setup.py` | modificar | Remover `return contextlib.nullcontext()` de `_on_status` |
| `backend/services/agent_adapter.py` | modificar | Corrigir type hints de `get_user_id()`, `inject_user_context(project_id)` e o `or 0` |
| `backend/services/setup_agent.py` | modificar | Corrigir type hint `user_id: int` + propagar exceções em `chat()` |
| `src/application/agent_service.py` | modificar | Adicionar `is_auth_error` em `invoke_with_callbacks` |
| `rag_service/_streaming.py` | modificar | Substituir `get_event_loop()` por `get_running_loop()` |
| `rag_service/main.py` | modificar | Limite de upload em `/ingest` e `/store` |

---

## Sequência de Execução

### Passo 1 — [ALTO] Corrigir Account Takeover no Callback GitHub OAuth

**Arquivo:** `backend/routers/auth_github.py`

**O que fazer:**

1. Na função `_github_callback_inner`, restringir o fallback de busca por `login` apenas
   a contas criadas via seed (sem `email` e sem `github_id`), nunca a contas de e-mail.

```python
# ANTES
if not user:
    user = db.exec(select(User).where(User.login == login)).first()

# DEPOIS
if not user:
    user = db.exec(
        select(User)
        .where(User.login == login)
        .where(User.github_id == None)   # só placeholders sem github_id
        .where(User.email == None)        # nunca sequestrar conta de e-mail
    ).first()
```

2. No mesmo arquivo, corrigir o `_ALLOWED_DOMAIN` para garantir lowercase:

```python
# ANTES
_ALLOWED_DOMAIN = os.getenv("ALLOWED_EMAIL_DOMAIN", "@sp.senai.br")

# DEPOIS
_ALLOWED_DOMAIN = os.getenv("ALLOWED_EMAIL_DOMAIN", "@sp.senai.br").lower()
```

**Dependências:** nenhuma

---

### Passo 2 — [MÉDIO] Emitir Erro quando `db_user` for `None` no Poll Copilot

**Arquivo:** `backend/routers/auth_copilot.py`

**O que fazer:** substituir o bloco `if db_user:` por um guard com `return` explícito:

```python
# ANTES
db_user = db.exec(select(User).where(User.id == user.id)).first()
if db_user:
    db_user.encrypted_llm_token = encrypted
    ...
    db.commit()

yield {"data": json.dumps({"type": "done", ...})}

# DEPOIS
db_user = db.exec(select(User).where(User.id == user.id)).first()
if not db_user:
    yield {"data": json.dumps({"type": "error", "detail": "Usuário não encontrado no banco."})}
    return

db_user.encrypted_llm_token = encrypted
...
db.commit()

yield {"data": json.dumps({"type": "done", ...})}
```

**Dependências:** nenhuma

---

### Passo 3 — [MÉDIO] Corrigir Type Hints e o `or 0` em `agent_adapter.py`

**Arquivo:** `backend/services/agent_adapter.py`

**O que fazer:**

1. Corrigir `get_user_id()` de `int | None` para `str | None`:

```python
def get_user_id(self) -> str | None:
    return self._state.user_id
```

2. Corrigir `inject_user_context` de `project_id: int | None` para `project_id: str | None`:

```python
def inject_user_context(self, user_id: str, session_id: str, project_id: str | None = None) -> None:
```

3. Corrigir o `or 0` em `chat_with_callbacks` (o fallback agora é string vazia):

```python
# ANTES
user_id=self._service.get_user_id() or 0,

# DEPOIS
user_id=self._service.get_user_id() or "",
```

**Dependências:** nenhuma

---

### Passo 4 — [MÉDIO] Corrigir Type Hints e Propagação de Exceções em `setup_agent.py`

**Arquivo:** `backend/services/setup_agent.py`

**O que fazer:**

1. Corrigir `_save_session_to_db` de `user_id: int` para `user_id: str` e remover os
   `# type: ignore[arg-type]` nos call sites:

```python
def _save_session_to_db(
    session_id: str,
    agent: SetupAgentService,
    user_id: str,    # era int
    db: Session,
) -> None:
```

2. Propagar exceções em `SetupAgentService.chat()` em vez de retornar string de erro.
   O handler SSE em `templates_setup.py` já possui `try/except Exception as e` que
   emite `{"type": "error", "message": str(e)}`:

```python
# ANTES
try:
    result = self._agent.invoke({"messages": self._messages})
except Exception as e:
    self._messages.pop()
    return f"Erro ao processar a mensagem: {e}"

# DEPOIS
try:
    result = self._agent.invoke({"messages": self._messages})
except Exception:
    self._messages.pop()
    raise   # propaga — o handler SSE converte em {"type": "error"}
```

**Dependências:** nenhuma

---

### Passo 5 — [MÉDIO] Limite de Tamanho de Upload em `project_files.py`

**Arquivo:** `backend/routers/project_files.py`

**O que fazer:**

1. Adicionar constante de limite e verificação após leitura do arquivo:

```python
_MAX_UPLOAD_BYTES = 100 * 1024 * 1024  # 100 MB

# Na função upload_project_file, após `data = await file.read()`:
if len(data) > _MAX_UPLOAD_BYTES:
    raise HTTPException(
        status_code=413,
        detail="O arquivo excede o limite máximo de 100 MB.",
    )
```

2. Corrigir o type hint de `_get_user_project`:

```python
# ANTES
def _get_user_project(project_id: int, user_id: str, db: Session) -> Project:

# DEPOIS
def _get_user_project(project_id: str, user_id: str, db: Session) -> Project:
```

**Dependências:** nenhuma

---

### Passo 6 — [MÉDIO] Limite de Upload no `rag_service/main.py`

**Arquivo:** `rag_service/main.py`

**O que fazer:** adicionar a mesma constante e verificação nos endpoints `/ingest` e `/store`:

```python
_MAX_UPLOAD_BYTES = 100 * 1024 * 1024  # 100 MB

# Em ingest() e store_file(), após `data = await file.read()`:
if len(data) > _MAX_UPLOAD_BYTES:
    raise HTTPException(status_code=413, detail="Arquivo excede o limite de 100 MB.")
```

**Dependências:** nenhuma

---

### Passo 7 — [BAIXO] Adicionar `is_auth_error` em `invoke_with_callbacks`

**Arquivo:** `src/application/agent_service.py`

**O que fazer:** espelhar o tratamento de `is_auth_error` que já existe em `chat()`:

```python
# ANTES
except Exception:
    self._messages.pop()
    raise

# DEPOIS
except Exception as e:
    self._messages.pop()
    if is_auth_error(e):
        raise ConnectionError(
            "Token inválido ou expirado. Reconecte suas credenciais nas preferências."
        ) from e
    raise
```

**Dependências:** nenhuma (`is_auth_error` já está importado no módulo)

---

### Passo 8 — [BAIXO] Limpeza do Arquivo Temporário em `_resolve_pptx_path`

**Arquivo:** `backend/routers/pptx.py`

**O que fazer:** o `_resolve_pptx_path` não pode fazer o cleanup por si só (retorna o path
para uso posterior). A solução é mover a criação para `tempfile.NamedTemporaryFile` com
`delete=False` e documentar que o chamador é responsável pela limpeza.
A alternativa mais simples: usar um diretório de cache com TTL em vez de `/tmp` puro.

Solução pragmática — no retorno, usar `tempfile.mkstemp` e adicionar comentário explícito:

```python
import tempfile

def _resolve_pptx_path(record: PptxFile) -> Path:
    local_path = _DATA_DIR / record.filename
    if local_path.exists():
        return local_path

    stream = _stream_from_minio(record.filename)
    if stream is None:
        raise HTTPException(
            status_code=404,
            detail=f"Arquivo '{record.filename}' não encontrado.",
        )

    # Usa mkstemp para evitar colisão de nomes e facilitar auditoria de /tmp
    fd, tmp_str = tempfile.mkstemp(suffix=".pptx")
    tmp_path = Path(tmp_str)
    try:
        with os.fdopen(fd, "wb") as f:
            for chunk in stream:
                f.write(chunk)
    except Exception:
        tmp_path.unlink(missing_ok=True)
        raise
    # Nota: o chamador é responsável por limpar tmp_path após o uso.
    # Em endpoints de preview (slides), o cache do Gotenberg já persiste o resultado.
    return tmp_path
```

**Dependências:** nenhuma

---

### Passo 9 — [BAIXO] Remover `return contextlib.nullcontext()` em `templates_setup.py`

**Arquivo:** `backend/routers/templates_setup.py`

**O que fazer:** remover o retorno e o import de `contextlib` se não usado em outro lugar:

```python
# ANTES
def _on_status(label: str):
    loop.call_soon_threadsafe(status_queue.put_nowait, label)
    return contextlib.nullcontext()

# DEPOIS
def _on_status(label: str) -> None:
    loop.call_soon_threadsafe(status_queue.put_nowait, label)
```

Verificar e remover `import contextlib` se não houver outro uso no arquivo.

**Dependências:** nenhuma

---

### Passo 10 — [BAIXO] Substituir `get_event_loop()` por `get_running_loop()` no RAG

**Arquivo:** `rag_service/_streaming.py`

**O que fazer:**

```python
# ANTES
loop = asyncio.get_event_loop()

# DEPOIS
loop = asyncio.get_running_loop()
```

**Dependências:** nenhuma

---

### Passo 11 — [BAIXO] Adicionar Limite de Tamanho para `body.content` no Chat

**Arquivo:** `backend/routers/chat.py`

**O que fazer:** adicionar constante e validação antes de persistir a mensagem:

```python
_MAX_MESSAGE_CHARS = 10_000  # ~10 mil caracteres por mensagem

# Na função send_message, após `if not body.content.strip()`:
if len(body.content) > _MAX_MESSAGE_CHARS:
    raise HTTPException(
        status_code=400,
        detail=f"Mensagem excede o limite de {_MAX_MESSAGE_CHARS} caracteres.",
    )
```

**Dependências:** nenhuma

---

### Passo 12 — [BAIXO] Ocultar Detalhes de Exceção Interna no Upload de Arquivo

**Arquivo:** `backend/routers/project_files.py`

**O que fazer:** substituir a exposição do detalhe da exceção por mensagem genérica:

```python
# ANTES
raise HTTPException(status_code=500, detail=f"Erro ao armazenar arquivo: {e}")

# DEPOIS
logger.error("Erro ao armazenar arquivo no MinIO (file_id=%s): %s", pf.id, e)
raise HTTPException(
    status_code=500,
    detail="Erro ao armazenar o arquivo. Tente novamente ou contate o administrador.",
)
```

**Dependências:** nenhuma

---

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|---|---|---|
| Passo 1 quebra login de usuários seed existentes que já têm `github_id` | Baixa | O filtro `github_id == None` só afeta placeholders sem github_id; contas já vinculadas são encontradas na primeira query (`github_id == github_id`) |
| Passo 4 — propagação de exceções em `chat()` chega sem mensagem amigável | Baixa | O handler SSE em `setup_message` já captura `Exception as e` e emite `{"type": "error", "message": str(e)}` |
| Passo 5/6 — limite de 100 MB muito restritivo para alguns fluxos | Baixa | Valor configurável por constante; pode ser ajustado antes da execução sem impacto na lógica |
| Passo 8 — `_resolve_pptx_path` com `mkstemp` pode vazar fd em erro de stream | Baixa | O `try/except` fecha o fd e remove o arquivo antes de re-lançar a exceção |
| Passo 3 — mudar fallback de `or 0` para `or ""` pode quebrar chamadas que esperavam int | Baixa | `set_user_context` recebe `user_id: str`; o `or ""` é só fallback de segurança para None |

---

## Critérios de Conclusão

- [ ] `uv run ruff check .` → 0 erros
- [ ] `uv run pytest tests/` → todos os testes existentes passam
- [ ] `npm run build` → sem erros de TypeScript
- [ ] Cenário manual de account takeover não funciona mais:
  - Criar usuário email com login que coincide com login GitHub
  - Iniciar fluxo OAuth GitHub com esse login
  - Verificar que a conta de e-mail **não** teve `github_id` sobrescrito
- [ ] Upload de arquivo > 100 MB retorna HTTP 413
- [ ] Mensagem de chat com > 10.000 chars retorna HTTP 400
- [ ] Nenhuma string de exceção interna aparece em respostas HTTP de produção
- [ ] `uv run ruff check rag_service/` → 0 erros no serviço RAG
