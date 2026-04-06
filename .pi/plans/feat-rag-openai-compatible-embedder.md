# Plano: Embedder OpenAI-compatible no RAG por usuário

**Data:** 2026-04-04
**Autor:** agente-plan
**Status:** aprovado

---

## Objetivo

Permitir que cada usuário configure um embedder OpenAI-compatible (ex: OpenRouter, qualquer
API `/v1/embeddings`) como alternativa ao Ollama no RAG service. A configuração inclui URL,
API key, modelo e dimensão do embedding. Se não configurada, Ollama continua como padrão.
A configuração é individual por usuário e editável pelo frontend, na mesma seção de LLM.

---

## Estado atual após refatoração (commit 2d80096)

Antes de implementar esta feature, o pipeline de ingestão foi refatorado:

| Antes | Depois |
|---|---|
| `POST /ingest` recebia arquivo + fazia embedding (único endpoint) | `POST /store` armazena no MinIO; `POST /reprocess` faz embedding |
| `_ingest_background` criava `RagAdapter` com bytes em memória | Removida — apenas `_reprocess_background` existe |
| Uploads simultâneos causavam concorrência no Ollama | `ingest_queue.py`: `get_user_lock(user_id)` serializa por usuário |
| `reprocess_streaming` não enviava `project_id` | **Já corrigido** — `project_id` está no JSON body |
| `DELETE /files/{id}` reconstruía path MinIO incorretamente | **Já corrigido** — aceita `storage_key` como query param |

**Consequência para este plano:**
- O backend nunca mais chama `/ingest` — o fluxo é `/store` (sem embedding) + `/reprocess` (com embedding).
- Embed config deve ser propagada para `/reprocess`, `/search` e `/search/stems`.
- `/ingest` em `main.py` ainda existe mas é código legado; será atualizado por consistência, não por necessidade.
- `_reprocess_background` já recebe apenas primitivos — sem risco de `DetachedInstanceError`.

---

## Escopo

**Dentro do escopo:**
- Novos campos de RAG embed config no modelo `User` (provider, base_url, key, model, dimensions)
- Endpoint `PUT /users/me/rag-embed` no backend
- Suporte a `OpenAIDocumentEmbedder` / `OpenAITextEmbedder` no `rag_service/pipelines.py`
- Coleção Qdrant **por usuário** (`knowledge_{user_id}`) para isolar dimensões diferentes
- `store.py` vira factory keyed por `(user_id, embedding_dim)` com lock thread-safe
- Propagação da config de embedding em: `/reprocess`, `/search`, `/search/stems`
- Seção "Embedding da Base de Conhecimento" no frontend, inline abaixo da config de LLM
- Aviso no frontend quando dimensão muda (requer reprocessamento de todos os arquivos)
- Aviso no frontend ao fazer primeiro login após deploy (arquivos na coleção antiga precisam ser reprocessados)

**Fora do escopo:**
- Migração automática de dados de coleções antigas (usuários existentes reprocessam manualmente)
- Circuit breaker / fallback automático Ollama→OpenAI em caso de falha
- Suporte a `sentence-transformers` local sem Ollama
- Endpoint de "reset da coleção" (coberto pelo reprocess individual de arquivos)
- Validação de alcançabilidade de `base_url` no momento do cadastro

---

## Decisão de design crítica: coleção Qdrant por usuário

**Problema:** `store.py` atual usa uma única coleção `project_knowledge` com dimensão 4096
fixada para todos os usuários. Se diferentes usuários usam embedders com dimensões distintas
(ex: qwen3=4096, text-embedding-3-small=1536), os vetores são incompatíveis — Qdrant rejeita
a ingestão com erro de dimensão.

**Solução: coleção por usuário**
- Nome da coleção: `knowledge_{user_id}` (ex: `knowledge_abc123`)
- `get_store(user_id, embedding_dim)` → factory com cache dict `{(user_id, dim): store}`
- Cache protegido por `threading.Lock` (o rag_service usa Uvicorn; workers async podem
  criar coroutines concorrentes, mas a criação do store é sync — lock garante idempotência)
- Cada usuário tem sua própria coleção com a dimensão que configurou
- `project_id` ainda é filtrado no metadata para isolamento por projeto dentro da coleção
- `search.py` (busca léxica por stems) também usa `knowledge_{user_id}` — recebe apenas `user_id`

**Mudança de dimensão pelo usuário:**
- Se a dim mudar, a key `(user_id, dim)` é nova → novo `QdrantDocumentStore` criado
- Qdrant retorna erro de dimensão na primeira tentativa de ingest → arquivo vai a `status=error`
- O frontend exibe aviso ao salvar nova config com dimensão diferente da atual:
  "Alterar a dimensão do embedding invalida os arquivos indexados. Reprocesse todos os arquivos."

**Incompatibilidade com coleção anterior `project_knowledge` após deploy:**
- Usuários existentes têm arquivos com `status=ready` na coleção antiga — busca retornará vazio
- O frontend deve exibir um **banner de aviso** detectando que o usuário tem arquivos `ready`
  mas a coleção `knowledge_{user_id}` ainda não existe (primeira ingestão cria a coleção)
- Alternativa mais simples: exibir mensagem fixa na seção RAG: "Após atualização do sistema,
  reprocesse todos os seus arquivos para atualizar a base de conhecimento."
- A coleção antiga `project_knowledge` fica órfã; deve ser removida manualmente do Qdrant

---

## Arquivos Afetados

| Arquivo | Ação | Motivo |
|---|---|---|
| `backend/models/__init__.py` | modificar | 5 novos campos em `User` (provider, base_url, key, model, dimensions) |
| `backend/migrations/versions/<slug>.py` | criar | migration Alembic: `add_rag_embed_config_to_user` |
| `backend/routers/auth_github.py` | modificar | `UserOut` + `from_user()` expõem 4 novos campos ao frontend |
| `backend/routers/users.py` | modificar | novo endpoint `PUT /users/me/rag-embed` + schema |
| `backend/routers/project_files.py` | modificar | `_reprocess_background` + callers recebem e passam embed config como primitivos |
| `backend/services/agent_adapter.py` | modificar | `WebAgentService` carrega e repassa embed config ao `RagAdapter` |
| `src/infrastructure/rag_adapter.py` | modificar | `RagEmbedConfig` dataclass + propagação em `reprocess_streaming`, `search`, `search_by_stems` |
| `rag_service/store.py` | modificar | factory por `(user_id, embedding_dim)` + lock thread-safe + coleção `knowledge_{user_id}` |
| `rag_service/pipelines.py` | modificar | `EmbedConfig` dataclass + `_make_doc_embedder` / `_make_text_embedder` |
| `rag_service/main.py` | modificar | schemas de `/reprocess`, `/search`, `/search/stems` aceitam embed config; `/ingest` atualizado por consistência |
| `rag_service/search.py` | modificar | `search_by_stems` e `_scroll_stems` recebem `user_id` para derivar `collection_name` |
| `frontend/src/api/types.ts` | modificar | `User` com 4 novos campos RAG |
| `frontend/src/api/auth.ts` | modificar | nova função `saveRagEmbedConfig()` |
| `frontend/src/components/settings/LlmSettings.tsx` | modificar | renderiza `RagEmbedSettings` inline no final da seção |
| `frontend/src/components/settings/RagEmbedSettings.tsx` | criar | formulário de config do embedding RAG |

---

## Sequência de Execução

### 1. Modelo de dados — novos campos em `User`
**Arquivo:** `backend/models/__init__.py`

Adicionar ao final do modelo `User`:
```python
rag_embed_provider: str = Field(default="ollama")           # "ollama" | "openai_compatible"
rag_embed_base_url: str | None = None
encrypted_rag_embed_key: str | None = None
rag_embed_model: str = Field(default="qwen3-embedding:8b")
rag_embed_dimensions: int = Field(default=4096)
```

**Dependências:** nenhuma

---

### 2. Migration Alembic
**Arquivo:** `backend/migrations/versions/<slug>.py`

Gerar com:
```bash
uv run alembic revision --autogenerate -m "add_rag_embed_config_to_user"
```

Verificar que o autogenerate cria as 5 colunas com defaults corretos:
- `rag_embed_provider VARCHAR DEFAULT 'ollama' NOT NULL`
- `rag_embed_base_url VARCHAR NULL`
- `encrypted_rag_embed_key VARCHAR NULL`
- `rag_embed_model VARCHAR DEFAULT 'qwen3-embedding:8b' NOT NULL`
- `rag_embed_dimensions INTEGER DEFAULT 4096 NOT NULL`

**Dependências:** Passo 1

---

### 3. Backend — `UserOut` expõe os novos campos
**Arquivo:** `backend/routers/auth_github.py`

Adicionar a `UserOut`:
```python
rag_embed_provider: str
rag_embed_model: str
rag_embed_base_url: str | None
has_rag_embed_key: bool
rag_embed_dimensions: int
```

Atualizar `from_user()`:
```python
rag_embed_provider=user.rag_embed_provider,
rag_embed_model=user.rag_embed_model,
rag_embed_base_url=user.rag_embed_base_url,
has_rag_embed_key=bool(user.encrypted_rag_embed_key),
rag_embed_dimensions=user.rag_embed_dimensions,
```

**Dependências:** Passo 1

---

### 4. Backend — endpoint `PUT /users/me/rag-embed`
**Arquivo:** `backend/routers/users.py`

Novo schema de request:
```python
class UpdateRagEmbedRequest(BaseModel):
    """Payload para configurar o provider de embedding do RAG."""
    provider: str = "ollama"                # "ollama" | "openai_compatible"
    base_url: str | None = None             # obrigatório se openai_compatible
    embed_key: str | None = None            # None=manter; ""=limpar; valor=encriptar
    model: str = "qwen3-embedding:8b"
    dimensions: int = 4096
```

Validações:
- `provider` deve ser `"ollama"` ou `"openai_compatible"`
- Se `"openai_compatible"`, `base_url` é obrigatório (HTTP 400 caso ausente)
- `dimensions` deve ser > 0

Lógica do endpoint:
- Salvar provider, base_url, model, dimensions diretamente
- Se `embed_key is not None`: vazio → limpar; valor → `encrypt_token()` → salvar
- Retornar `{"provider": ..., "model": ..., "dimensions": ...}`

**Dependências:** Passo 1

---

### 5. RAG Service — `store.py` vira factory thread-safe
**Arquivo:** `rag_service/store.py`

Substituir o singleton por uma factory com cache por `(user_id, embedding_dim)` protegida
por `threading.Lock` (sem race condition em múltiplas coroutines):

```python
import threading

_stores: dict[tuple[str, int], QdrantDocumentStore] = {}
_lock = threading.Lock()

def get_store(user_id: str, embedding_dim: int = 4096) -> QdrantDocumentStore:
    """Retorna QdrantDocumentStore isolado por usuário, criando a coleção se necessária.

    Thread-safe: usa lock para evitar criação duplicada em coroutines concorrentes.

    Args:
        user_id: ID do usuário — define o nome da coleção Qdrant.
        embedding_dim: Dimensão dos vetores — deve ser consistente com o embedder configurado.

    Returns:
        QdrantDocumentStore configurado para a coleção `knowledge_{user_id}`.
    """
    key = (user_id, embedding_dim)
    with _lock:
        if key not in _stores:
            index_name = f"knowledge_{user_id}"
            qdrant_url = os.environ.get("QDRANT_URL", "http://qdrant:6333")
            logger.info(
                "Inicializando QdrantDocumentStore: collection=%s, dim=%d", index_name, embedding_dim
            )
            _stores[key] = QdrantDocumentStore(
                url=qdrant_url,
                index=index_name,
                embedding_dim=embedding_dim,
                recreate_index=False,
                return_embedding=False,
            )
    return _stores[key]
```

**Nota sobre crescimento do cache:** cada entrada é um objeto leve (QdrantDocumentStore é lazy).
Com dezenas de usuários e poucos embedders distintos por usuário, o impacto em memória é desprezível.
Não há mecanismo de invalidação por mudança de modelo — a mudança de dimensão cria uma nova entry
automaticamente pela key `(user_id, nova_dim)`.

**Dependências:** nenhuma

---

### 6. RAG Service — `EmbedConfig` e embedders em `pipelines.py`
**Arquivo:** `rag_service/pipelines.py`

Verificar versão do `haystack-ai` antes de implementar:
```bash
grep "haystack-ai" rag_service/pyproject.toml
```
`Secret.from_token(str)` está disponível desde `haystack-ai>=2.0`. Se a versão for mais antiga,
atualizar para `haystack-ai>=2.9` no `pyproject.toml` do rag_service.

Adicionar dataclass no topo do módulo:
```python
import dataclasses

@dataclasses.dataclass
class EmbedConfig:
    """Configuração do embedder: provider, credenciais e modelo."""
    provider: str = "ollama"            # "ollama" | "openai_compatible"
    base_url: str = ""
    api_key: str = ""                   # nunca logar este campo
    model: str = ""                     # "" = usar _EMBED_MODEL como fallback
    dimensions: int = 4096
```

Adicionar helpers privados:
```python
def _make_doc_embedder(cfg: EmbedConfig) -> Any:
    """Cria DocumentEmbedder conforme o provider configurado."""
    if cfg.provider == "openai_compatible":
        from haystack.components.embedders import OpenAIDocumentEmbedder
        from haystack.utils import Secret
        logger.debug(
            "Usando OpenAIDocumentEmbedder: base_url=%s, model=%s, api_key=%s",
            cfg.base_url, cfg.model, "<set>" if cfg.api_key else "<empty>",
        )
        return OpenAIDocumentEmbedder(
            model=cfg.model or _EMBED_MODEL,
            api_base_url=cfg.base_url,
            api_key=Secret.from_token(cfg.api_key),
        )
    return OllamaDocumentEmbedder(
        model=cfg.model or _EMBED_MODEL, url=_ollama_url(), batch_size=1, timeout=120
    )

def _make_text_embedder(cfg: EmbedConfig) -> Any:
    """Cria TextEmbedder conforme o provider configurado."""
    if cfg.provider == "openai_compatible":
        from haystack.components.embedders import OpenAITextEmbedder
        from haystack.utils import Secret
        logger.debug(
            "Usando OpenAITextEmbedder: base_url=%s, model=%s, api_key=%s",
            cfg.base_url, cfg.model, "<set>" if cfg.api_key else "<empty>",
        )
        return OpenAITextEmbedder(
            model=cfg.model or _EMBED_MODEL,
            api_base_url=cfg.base_url,
            api_key=Secret.from_token(cfg.api_key),
        )
    return OllamaTextEmbedder(model=cfg.model or _EMBED_MODEL, url=_ollama_url())
```

Alterar assinaturas de `ingest_file_stream` e `search_documents`:
```python
def ingest_file_stream(
    file_path: Path,
    metadata: dict[str, Any],
    embed_cfg: EmbedConfig | None = None,
) -> Generator[dict[str, Any], None, None]:
    cfg = embed_cfg or EmbedConfig()
    store = get_store(metadata["user_id"], cfg.dimensions)
    embedder = _make_doc_embedder(cfg)
    ...  # resto igual, substituindo OllamaDocumentEmbedder por embedder

def search_documents(
    query: str,
    project_id: str,
    user_id: str,
    top_k: int = _TOP_K,
    embed_cfg: EmbedConfig | None = None,
) -> list[dict[str, Any]]:
    cfg = embed_cfg or EmbedConfig()
    store = get_store(user_id, cfg.dimensions)
    embedder = _make_text_embedder(cfg)
    ...  # resto igual, substituindo OllamaTextEmbedder por embedder
```

`delete_file_chunks` não usa embedding — sem mudanças.

**Dependências:** Passo 5

---

### 7. RAG Service — schemas e endpoints em `main.py`
**Arquivo:** `rag_service/main.py`

**Campos de embed config comuns** (adicionar a `SearchRequest` e `ReprocessRequest`):
```python
embed_provider: str = "ollama"
embed_base_url: str = ""
embed_api_key: str = ""         # plaintext (canal interno — nunca logar)
embed_model: str = ""           # "" = usar default do provider
embed_dimensions: int = 4096
```

**`ReprocessRequest`** (principal caminho de ingestão):
```python
class ReprocessRequest(BaseModel):
    file_id: str
    project_id: str
    user_id: str
    filename: str
    storage_key: str
    embed_provider: str = "ollama"
    embed_base_url: str = ""
    embed_api_key: str = ""
    embed_model: str = ""
    embed_dimensions: int = 4096
```

**`SearchRequest`**:
```python
class SearchRequest(BaseModel):
    query: str
    project_id: str
    user_id: str
    top_k: int = 5
    rerank: bool = False
    rerank_top_k: int = 20
    embed_provider: str = "ollama"
    embed_base_url: str = ""
    embed_api_key: str = ""
    embed_model: str = ""
    embed_dimensions: int = 4096
```

**`/ingest`** (Form — atualizado por consistência, não é o caminho principal):
```python
embed_provider: str = Form(default="ollama"),
embed_base_url: str = Form(default=""),
embed_api_key: str = Form(default=""),
embed_model: str = Form(default=""),
embed_dimensions: int = Form(default=4096),
```

**Em cada endpoint**, construir `EmbedConfig` antes de chamar pipelines:
```python
from rag_service.pipelines import EmbedConfig
cfg = EmbedConfig(
    provider=body.embed_provider,       # ou param de Form
    base_url=body.embed_base_url,
    api_key=body.embed_api_key,
    model=body.embed_model,
    dimensions=body.embed_dimensions,
)
```

**`/store` não recebe embed config** — apenas armazena no MinIO, sem embedding.

**Dependências:** Passo 6

---

### 8. RAG Service — `search.py` usa coleção por usuário
**Arquivo:** `rag_service/search.py`

`search_by_stems` e `_scroll_stems` usam `"project_knowledge"` hardcoded.
Atualizar para derivar a coleção pelo `user_id`:

```python
def _scroll_stems(
    project_id: str,
    user_id: str,
    stems: list[str],
    top_k: int,
) -> list[Any]:
    """Executa scroll no Qdrant com filtro de radicais na coleção do usuário."""
    collection_name = f"knowledge_{user_id}"
    try:
        results, _ = _get_qdrant_client().scroll(
            collection_name=collection_name,
            scroll_filter=_build_stem_filter(project_id, user_id, stems),
            limit=top_k,
            with_payload=True,
            with_vectors=False,
        )
        return list(results)
    except Exception as e:
        logger.error("Erro na busca por radicais (collection=%s): %s", collection_name, e)
        return []
```

`search_by_stems` não recebe `embed_dimensions` — a coleção é derivada apenas do `user_id`.
A assinatura permanece:
```python
def search_by_stems(
    query: str,
    project_id: str,
    user_id: str,
    top_k: int = _TOP_K,
) -> list[dict[str, Any]]:
```

**Dependências:** Passo 5

---

### 9. `RagAdapter` — `RagEmbedConfig` e propagação
**Arquivo:** `src/infrastructure/rag_adapter.py`

Adicionar dataclass no topo:
```python
import dataclasses

@dataclasses.dataclass
class RagEmbedConfig:
    """Config de embedding do RAG, decriptada, pronta para envio ao rag_service."""
    provider: str = "ollama"
    base_url: str = ""
    api_key: str = ""           # plaintext — nunca logar
    model: str = ""
    dimensions: int = 4096
```

Atualizar `RagAdapter.__init__`:
```python
def __init__(self, embed_cfg: RagEmbedConfig | None = None) -> None:
    self._embed_cfg = embed_cfg or RagEmbedConfig()
```

**`store_file`**: não usa embedding — **sem mudanças**.

**`reprocess_streaming`** (caminho principal de ingestão): adicionar ao JSON body:
```python
content=json.dumps({
    "file_id": file_id,
    "project_id": project_id,
    "user_id": user_id,
    "filename": filename,
    "storage_key": storage_key,
    "embed_provider": self._embed_cfg.provider,
    "embed_base_url": self._embed_cfg.base_url,
    "embed_api_key": self._embed_cfg.api_key,
    "embed_model": self._embed_cfg.model,
    "embed_dimensions": self._embed_cfg.dimensions,
})
```

**`search`**: adicionar ao JSON body:
```python
json={
    "query": query,
    "project_id": project_id,
    "user_id": user_id,
    "top_k": top_k,
    "rerank": rerank,
    "rerank_top_k": rerank_top_k,
    "embed_provider": self._embed_cfg.provider,
    "embed_base_url": self._embed_cfg.base_url,
    "embed_api_key": self._embed_cfg.api_key,
    "embed_model": self._embed_cfg.model,
    "embed_dimensions": self._embed_cfg.dimensions,
}
```

**`search_by_stems`**: adicionar ao JSON body:
```python
json={
    "query": query,
    "project_id": project_id,
    "user_id": user_id,
    "top_k": top_k,
    "embed_provider": self._embed_cfg.provider,
    "embed_base_url": self._embed_cfg.base_url,
    "embed_api_key": self._embed_cfg.api_key,
    "embed_model": self._embed_cfg.model,
    "embed_dimensions": self._embed_cfg.dimensions,
}
```

**`delete_file`**: não usa embedding — **sem mudanças**.

**`ingest_streaming` / `ingest`**: são dead code (não chamados pelo backend desde o commit 2d80096).
Atualizar para consistência adicionando `embed_cfg` como parâmetro e passando os campos ao Form,
mas não são o caminho crítico.

**Dependências:** Passo 7

---

### 10. `WebAgentService` — carrega e repassa embed config
**Arquivo:** `backend/services/agent_adapter.py`

Em `__init__`, após decriptar o token LLM, decriptar também o embed key:
```python
from src.infrastructure.rag_adapter import RagEmbedConfig

rag_embed_key = (
    decrypt_token(user.encrypted_rag_embed_key)
    if user.encrypted_rag_embed_key
    else ""
)
self._rag_embed_cfg = RagEmbedConfig(
    provider=user.rag_embed_provider,
    base_url=user.rag_embed_base_url or "",
    api_key=rag_embed_key,
    model=user.rag_embed_model,
    dimensions=user.rag_embed_dimensions,
)
```

Em `inject_user_context`, criar `RagAdapter` com a config:
```python
from src.infrastructure.rag_adapter import RagAdapter
self._service._state.rag = RagAdapter(embed_cfg=self._rag_embed_cfg)
```

**Dependências:** Passos 1, 9

---

### 11. `project_files.py` — embed config em `_reprocess_background`
**Arquivo:** `backend/routers/project_files.py`

`_reprocess_background` já recebe primitivos (sem objetos SQLAlchemy) — sem risco de
`DetachedInstanceError`. Adicionar os campos de embed config como parâmetros primitivos:

```python
async def _reprocess_background(
    file_id: str,
    project_id: str,
    user_id: str,
    original_name: str,
    storage_key: str,
    embed_provider: str = "ollama",
    embed_base_url: str = "",
    embed_api_key: str = "",
    embed_model: str = "",
    embed_dimensions: int = 4096,
) -> None:
    from backend.db import engine
    from backend.services.ingest_queue import get_user_lock
    from src.infrastructure.rag_adapter import RagAdapter, RagEmbedConfig

    cfg = RagEmbedConfig(
        provider=embed_provider,
        base_url=embed_base_url,
        api_key=embed_api_key,
        model=embed_model,
        dimensions=embed_dimensions,
    )
    adapter = RagAdapter(embed_cfg=cfg)
    async with get_user_lock(str(user_id)):
        await _run_ingest_stream(
            stream=adapter.reprocess_streaming(
                file_id=file_id,
                project_id=project_id,
                user_id=user_id,
                filename=original_name,
                storage_key=storage_key,
            ),
            file_id=file_id,
            engine=engine,
        )
```

**Em `upload_project_file`**, extrair embed config do `user` como primitivos **antes** de
criar a background task (os bytes do `User` SQLAlchemy já estão disponíveis no escopo do endpoint):
```python
rag_embed_key = (
    decrypt_token(user.encrypted_rag_embed_key)
    if user.encrypted_rag_embed_key
    else ""
)
background_tasks.add_task(
    _reprocess_background,
    file_id=pf.id,
    project_id=project_id,
    user_id=pf.user_id,
    original_name=original_name,
    storage_key=storage_key,
    embed_provider=user.rag_embed_provider,
    embed_base_url=user.rag_embed_base_url or "",
    embed_api_key=rag_embed_key,
    embed_model=user.rag_embed_model,
    embed_dimensions=user.rag_embed_dimensions,
)
```

**Em `reprocess_project_file`**, mesma extração de primitivos antes do `background_tasks.add_task`.

**Dependências:** Passos 1, 9

---

### 12. Frontend — `api/types.ts`
**Arquivo:** `frontend/src/api/types.ts`

Adicionar a `User`:
```typescript
rag_embed_provider: string;
rag_embed_model: string;
rag_embed_base_url: string | null;
has_rag_embed_key: boolean;
rag_embed_dimensions: number;
```

**Dependências:** Passo 3

---

### 13. Frontend — `api/auth.ts`
**Arquivo:** `frontend/src/api/auth.ts`

Nova função (ou em `api/users.ts` se já existir):
```typescript
export async function saveRagEmbedConfig(body: {
  provider: string;
  base_url: string | null;
  embed_key: string | null;
  model: string;
  dimensions: number;
}): Promise<void> {
  const res = await fetch("/api/users/me/rag-embed", {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new Error(data.detail ?? "Erro ao salvar configuração de embedding.");
  }
}
```

**Dependências:** Passo 4

---

### 14. Frontend — `RagEmbedSettings.tsx`
**Arquivo:** `frontend/src/components/settings/RagEmbedSettings.tsx`

Componente standalone. Recebe `user` e `refetch` via props (passados por `LlmSettings`
que já tem acesso ao contexto de autenticação):

```typescript
interface Props {
  user: User;
  refetch: () => Promise<void>;
}
export function RagEmbedSettings({ user, refetch }: Props) { ... }
```

**Campos:**
- Select **Provider**: `ollama` | `openai_compatible`
- Se `openai_compatible`:
  - Input **Base URL** (obrigatório, `type="url"`)
  - Input **API Key** (senha, placeholder "deixe vazio para manter a atual" se `has_rag_embed_key`)
  - Input **Modelo** (text, ex: `text-embedding-3-small`)
  - Input **Dimensões** (`type="number"`, min=1, ex: `1536`)
- Se `ollama`:
  - Input **Modelo** (text, default `qwen3-embedding:8b`)
  - Input **Dimensões** (`type="number"`, default `4096`)
- Aviso inline quando `dimensions !== user.rag_embed_dimensions` (de qualquer provider):
  ```
  ⚠️ Alterar as dimensões invalida os vetores existentes.
  Todos os arquivos precisarão ser reprocessados após salvar.
  ```
- Banner fixo de migração pós-deploy:
  ```
  ℹ️ Após atualizações do sistema, reprocesse todos os seus arquivos
  para garantir que estão na base de conhecimento atualizada.
  ```
- Botão Salvar + estados idle/salvando/salvo/erro

**Lógica de submit:**
- Chamar `saveRagEmbedConfig({ provider, base_url, embed_key, model, dimensions })`
- `embed_key`: `null` se campo vazio (manter); valor se preenchido
- `await refetch()` após sucesso

**Derivar estado inicial dos campos** a partir de `user.rag_embed_*` (não armazenar em
`useState` derivado — calcular inline no `useMemo` ou inicializar apenas uma vez com
`useState(() => user.rag_embed_model)` no mount).

**Dependências:** Passos 12, 13

---

### 15. Frontend — `LlmSettings.tsx` renderiza `RagEmbedSettings`
**Arquivo:** `frontend/src/components/settings/LlmSettings.tsx`

`LlmSettings` já tem acesso a `user` e `refetch` via contexto de autenticação ou props.
Adicionar ao final do `return`, dentro do card, após o bloco Copilot:

```tsx
<hr className="border-zinc-800" />
<RagEmbedSettings user={user} refetch={refetch} />
```

Importar `RagEmbedSettings` no topo do arquivo.

**Dependências:** Passo 14

---

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|---|---|---|
| `Secret.from_token` indisponível na versão Haystack instalada | média | **verificar antes do Passo 6**: `grep "haystack-ai" rag_service/pyproject.toml`; atualizar para `>=2.9` se necessário |
| API key de embedding exposta em logs | alta | **nunca** logar `cfg.api_key` ou `embed_api_key`; usar `"<set>"` / `"<empty>"` em debug logs |
| API key trafega em plaintext no canal backend→rag_service | baixa | canal é rede Docker interna; documentar que TLS entre serviços é recomendado em produção pública |
| Coleção antiga `project_knowledge` fica órfã | baixa | documentar no README; remover manualmente do Qdrant após migração |
| Usuários existentes perdem busca silenciosamente após deploy | média | banner fixo na seção RAG orienta o reprocessamento; nova ingest vai para `knowledge_{user_id}` automaticamente |
| Dim mismatch: usuário muda dim sem reprocessar | média | Qdrant rejeita vetores com dim errada → arquivo vai a `status=error`; aviso no frontend ao salvar nova dimensão mitiga surpresa |
| `openai` não instalado no rag_service | baixa | `haystack-ai` já depende de `openai`; se CI falhar, adicionar `openai>=1.0` em `rag_service/pyproject.toml` |
| `RagEmbedSettings` não tem acesso a `user`/`refetch` | média | componente recebe via props de `LlmSettings` — garantir que `LlmSettings` já expõe esses dados antes de implementar o Passo 14 |

---

## Critérios de Conclusão

- [ ] `uv run alembic upgrade head` aplica migration sem erro
- [ ] `uv run pytest tests/` → todos os testes passam
- [ ] `npm run build` → sem erros TypeScript
- [ ] `uv run ruff check .` → 0 erros
- [ ] Com Ollama configurado (padrão): upload + reprocess funcionam como antes, usando coleção `knowledge_{user_id}`
- [ ] Com OpenAI-compatible configurado: reprocess usa `OpenAIDocumentEmbedder`, busca usa `OpenAITextEmbedder`
- [ ] Frontend exibe seção "Embedding da Base de Conhecimento" dentro do card de LLM
- [ ] Aviso de reprocessamento aparece ao mudar dimensões
- [ ] API key de embedding não aparece em nenhum log do backend ou do rag_service
- [ ] Usuário A não consegue ver documentos do usuário B (isolamento por coleção mantido)
- [ ] `store.py`: dois uploads simultâneos do mesmo usuário não criam dois stores para a mesma key (lock funciona)

---

## Notas de Implementação

### Verificar `Secret.from_token` no Haystack instalado
Antes de implementar o Passo 6:
```bash
grep "haystack-ai" rag_service/pyproject.toml
```
`Secret.from_token(str)` disponível desde `haystack-ai>=2.0`. Se a versão for mais antiga,
atualizar `haystack-ai>=2.9` antes de escrever o código.

### `ingest_streaming` / `ingest` no RagAdapter são dead code
Desde o commit `2d80096`, o backend não chama mais `/ingest` diretamente — o fluxo é
`/store` (sync) + `/reprocess` (background). Os métodos `ingest_streaming` e `ingest`
em `RagAdapter` ainda existem mas não são chamados. Atualizá-los com `embed_cfg` é
opcional e deve ser feito por último, sem prioridade.

### `_reprocess_background` é a única função de ingestão
`_ingest_background` foi removida no commit `2d80096`. Toda lógica de ingestão (upload
novo e reprocessamento) passa por `_reprocess_background`. Não recriar `_ingest_background`.

### Segurança: API key não deve aparecer em logs
Em qualquer log de debug que mencione `EmbedConfig` ou `RagEmbedConfig`, substituir
`api_key` por `"<set>"` se preenchido ou `"<empty>"` se vazio. Nunca logar o valor real.
