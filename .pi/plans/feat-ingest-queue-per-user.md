# Plano: Serialização de ingestão por usuário com posição na fila

**Data:** 2026-04-04
**Autor:** agente-plan
**Status:** aprovado

---

## Objetivo

Serializar a ingestão de arquivos no Ollama **por usuário**: cada usuário processa um
arquivo por vez; os demais aguardam em fila com posição visível na UI ("1ª na fila",
"2ª na fila" ...) em vez do genérico "Aguardando".

---

## Diagnóstico (causa raiz)

`ingest_file_stream` (`rag_service/pipelines.py`) roda cada arquivo em thread
independente via `iter_sync_gen`. Com N uploads simultâneos, N threads chamam
`OllamaDocumentEmbedder.run()` ao mesmo tempo. O Ollama não suporta concorrência —
os chunks atingem `timeout=120s` e são descartados silenciosamente com
`logger.warning`. O `chunks_indexed` final reflete apenas os chunks embeddados
antes das falhas.

---

## Escopo

**Dentro do escopo:**
- `asyncio.Lock` por `user_id` em memória — serializa ingestão e reprocessamento
- `queue_position: int | null` computado no endpoint de listagem — posição 1-indexed
  entre os arquivos do usuário ainda não finalizados (`pending` / `processing`),
  ordenados por `created_at`
- Badge "Xª na fila" no `ProjectFileList.tsx` substituindo "Aguardando"

**Fora do escopo:**
- Persistência da fila em banco (restart reseta a fila; botão "Reprocessar" já cobre)
- Serialização global entre usuários
- SSE/push para atualizar posição em tempo real (polling de 3 s já existe)

---

## Arquivos afetados

| Arquivo | Ação | Motivo |
|---|---|---|
| `backend/services/ingest_queue.py` | **criar** | Registry de `asyncio.Lock` por `user_id` |
| `backend/routers/project_files.py` | **modificar** | Lock em `_ingest_background` e `_reprocess_background`; `queue_position` em `ProjectFileOut` e `list_project_files` |
| `frontend/src/api/types.ts` | **modificar** | Adicionar `queue_position: number \| null` em `ProjectFile` |
| `frontend/src/components/ProjectFileList.tsx` | **modificar** | `StatusBadge` exibe "Xª na fila" para `status=pending` |

**Sem migration de banco** — `queue_position` é calculado, não armazenado.

---

## Sequência de Execução

### 1. Criar `backend/services/ingest_queue.py`

**Arquivo:** `backend/services/ingest_queue.py`  
**Dependências:** nenhuma

```python
"""Registry de asyncio.Lock por usuário para serializar ingestão no Ollama."""
import asyncio
_locks: dict[str, asyncio.Lock] = {}

def get_user_lock(user_id: str) -> asyncio.Lock:
    if user_id not in _locks:
        _locks[user_id] = asyncio.Lock()
    return _locks[user_id]
```

---

### 2. Novo endpoint `POST /store` em `rag_service/main.py`

Separa upload de embedding. O request HTTP retorna só após o MinIO confirmar o
upload; a BackgroundTask **não carrega mais bytes em memória**.

```python
@app.post("/store", response_model=dict[str, str])
async def store_file(
    file: UploadFile = File(...),
    file_id: str = Form(...),
    project_name: str = Form(...),
    user_id: str = Form(...),
    _: None = Depends(_require_secret),
) -> dict[str, str]:
    original_name = file.filename or "arquivo"
    content_type = file.content_type or "application/octet-stream"
    data = await file.read()
    key = minio_client.storage_key(user_id, project_name, file_id, original_name)
    try:
        minio_client.upload_file(key, data, content_type)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erro ao salvar arquivo: {e}")
    return {"storage_key": key}
```

**Dependências:** nenhuma.

---

### 3. Adicionar `store_file()` e corrigir `reprocess_streaming()` em `src/infrastructure/rag_adapter.py`

**3a. `store_file()`** — chama `POST /store`, retorna `storage_key`:

```python
async def store_file(self, file_id, project_name, user_id, filename, data, content_type) -> str:
    url = f"{_rag_url()}/store"
    async with httpx.AsyncClient(timeout=httpx.Timeout(
        connect=_CONNECT_TIMEOUT, read=120.0, write=120.0, pool=30.0
    )) as client:
        resp = await client.post(
            url, headers=_headers(),
            files={"file": (filename, data, content_type)},
            data={"file_id": str(file_id), "project_name": project_name, "user_id": str(user_id)},
        )
        resp.raise_for_status()
        return resp.json()["storage_key"]
```

**3b. `reprocess_streaming()`** — adicionar `project_id` (bug pré-existente: chunks
reprocessados ficavam sem `project_id` no Qdrant e nunca retornavam em buscas):

```python
async def reprocess_streaming(
    self, file_id: str, project_id: str, user_id: str, filename: str, storage_key: str,
) -> AsyncGenerator:
    # ...
    content=json.dumps({
        "file_id": file_id, "project_id": project_id,  # NOVO
        "user_id": user_id, "filename": filename, "storage_key": storage_key,
    })
```

**Dependências:** passo 2.

---

### 4. Refatorar `backend/routers/project_files.py`

#### 4a. `ProjectFileOut` — adicionar `queue_position: int | None`

#### 4b. `list_project_files` — calcular posição na fila

Query extra: todos os `ProjectFile` do usuário com `status="pending"` ordenados por
`created_at ASC` (fila global por usuário). `queue_position = idx + 1` para cada.

#### 4c. `upload_project_file` — upload-first (não mais bytes na BackgroundTask)

Fluxo:
1. Lê arquivo
2. Cria `ProjectFile(status="pending")` → obtém o `pf.id` para usar na `storage_key`
3. `await adapter.store_file(...)` → recebe `storage_key` (MinIO confirma antes do response)
4. Salva `pf.storage_key = storage_key` no banco
5. Despacha `_reprocess_background(file_id, project_id, user_id, original_name, storage_key)`

Se `store_file` falhar: deleta o registro órfão e retorna HTTP 500.

#### 4d. `reprocess_project_file` — passar `project_id` ao background task

```python
background_tasks.add_task(
    _reprocess_background,
    file_id=pf.id,
    project_id=pf.project_id,  # NOVO
    user_id=pf.user_id,
    original_name=pf.original_name,
    storage_key=pf.storage_key,
)
```

#### 4e. `_reprocess_background` — adicionar `project_id`; única função de ingestão

```python
async def _reprocess_background(
    file_id: str, project_id: str, user_id: str, original_name: str, storage_key: str,
) -> None:
    from backend.services.ingest_queue import get_user_lock
    from src.infrastructure.rag_adapter import RagAdapter
    adapter = RagAdapter()
    async with get_user_lock(str(user_id)):
        await _run_ingest_stream(
            stream=adapter.reprocess_streaming(
                file_id=file_id, project_id=project_id,
                user_id=user_id, filename=original_name, storage_key=storage_key,
            ),
            file_id=file_id, engine=engine,
        )
```

#### 4f. Remover `_ingest_background` (função obsoleta)

#### 4g. `_run_ingest_stream` — não sobrescrever `storage_key` no evento `done`

Remover `storage_key=sk` do `_update_file` no bloco `done` — a chave já está salva
before da task; sobrescrever com `""` quebraria o Fix 2. Corrigir `%d` → `%s`
nos format strings de log (file_id é str/UUID, não int).

**Dependências:** passos 1, 2, 3.

---

### 5. Modificar `frontend/src/api/types.ts`

```typescript
queue_position: number | null;  // posição 1-indexed na fila; null se não pendente
```

**Dependências:** passo 4b.

---

### 6. Modificar `frontend/src/components/ProjectFileList.tsx`

`StatusBadge` exibe `"Xª na fila"` para `status="pending"`:

```tsx
const label = file.queue_position != null ? `${file.queue_position}ª na fila` : "Aguardando";
```

**Dependências:** passo 5.

---

## Comportamento visual final

```
Arquivo A  🔄 Processando  12/47  ████████░░░░░░░░
Arquivo B  ⏳ 1ª na fila
Arquivo C  ⏳ 2ª na fila
Arquivo D  ⏳ 3ª na fila
Arquivo E  ⏳ 4ª na fila
Arquivo F  ⏳ 5ª na fila
```

Quando A termina, B entra em `processing`, C passa a `1ª na fila`, e assim por diante.
O polling de 3 s já existente em `ProjectDetail.tsx` mantém a UI atualizada.

---

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|---|---|---|
| Lock criado em contexto errado (não no event loop do app) | Baixa — `BackgroundTask` sempre corre no event loop principal | `asyncio.Lock()` criado no primeiro `get_user_lock` chamado do event loop correto |
| `async with` não libera o Lock se `_run_ingest_stream` lança exceção | Nula | `async with` garante `__aexit__` mesmo com exceção |
| Arquivo preso em `"processing"` após reinício do servidor | Baixa — pré-existente | Botão "Reprocessar" na UI (já existe) |
| Gunicorn multi-worker: Locks não compartilhados entre processos | Baixa — deploy usa `--workers 1` com Uvicorn | Documentar no README que múltiplos workers quebram a fila; usar `--workers 1` |
| `queue_position` desatualiza entre polls (3 s) | Baixa — tolerável | Polling já existente; sem impacto funcional |

---

---

# Fix 2: Deleção de arquivo não remove do MinIO nem do Qdrant

## Diagnóstico

Durante a deleção de um arquivo (`DELETE /projects/{id}/files/{id}`), o `rag_service`
precisa remover os chunks do Qdrant **e** o arquivo bruto do MinIO. O código atual
tenta reconstruir a chave MinIO localmente, mas usa `project_id` (UUID) onde a
função `storage_key()` espera `project_name` — gerando um caminho errado.

```
Ingest  → storage_key(user_id, project_name, ...) → "uid/pitch-q3-2026/fid_arq.pdf"
Delete  → storage_key(user_id, project_id,   ...) → "uid/abc-123-def-456/fid_arq.pdf"  ✗
```

`minio_client.delete_file()` silencia o `S3Error` com `logger.warning` — o arquivo
some da UI mas permanece no MinIO e os chunks permanecem no Qdrant.

A chave correta já existe em `ProjectFile.storage_key` (gravada no evento `"done"`
da ingestão), mas nunca é passada para o adapter na chamada de deleção.

## Arquivos afetados

| Arquivo | Ação | Motivo |
|---|---|---|
| `rag_service/main.py` | **modificar** | Endpoint `DELETE /files/{id}`: receber `storage_key` por query param e usá-la diretamente |
| `src/infrastructure/rag_adapter.py` | **modificar** | `delete_file`: passar `storage_key` em vez de `project_id`/`original_name`; corrigir type hints (`int` → `str`) |
| `src/ports/rag_port.py` | **modificar** | `delete_file` Protocol: trocar `project_id` + `original_name` por `storage_key: str` |
| `backend/routers/project_files.py` | **modificar** | `delete_project_file`: passar `pf.storage_key` ao adapter; guard para `storage_key` vazio |

**Sem migration de banco** — `storage_key` já existe em `ProjectFile`.

## Sequência de Execução

### Fix2-1. `rag_service/main.py` — endpoint DELETE

Substituir os params `user_id`, `project_id`, `original_name` por `storage_key`.
O Qdrant continua usando apenas `file_id`; o MinIO usa `storage_key` diretamente.

```python
@app.delete("/files/{file_id}", ...)
async def delete_file(
    file_id: str,
    storage_key: str,          # chave exata — sem reconstrução
    _: None = Depends(_require_secret),
) -> dict[str, str]:
    try:
        delete_file_chunks(file_id)
    except Exception as e:
        logger.warning("Erro ao remover chunks do Qdrant (file_id=%s): %s", file_id, e)

    if storage_key:
        minio_client.delete_file(storage_key)

    return {"detail": f"Arquivo {file_id} removido do Qdrant e do MinIO."}
```

**Dependências:** nenhuma.

### Fix2-2. `src/ports/rag_port.py` — assinatura do Protocol

Trocar `project_id: int` + `original_name: str` por `storage_key: str`:

```python
async def delete_file(
    self,
    file_id: str,
    storage_key: str,
) -> None:
    ...
```

**Dependências:** Fix2-1 (define o contrato novo).

### Fix2-3. `src/infrastructure/rag_adapter.py` — implementação

Atualizar `delete_file` para usar `storage_key` e corrigir type hints:

```python
async def delete_file(
    self,
    file_id: str,
    storage_key: str,
) -> None:
    url = f"{_rag_url()}/files/{file_id}"
    async with httpx.AsyncClient(timeout=httpx.Timeout(_READ_TIMEOUT)) as client:
        resp = await client.delete(
            url,
            headers=_headers(),
            params={"storage_key": storage_key},
        )
        resp.raise_for_status()
```

**Dependências:** Fix2-2.

### Fix2-4. `backend/routers/project_files.py` — chamada do adapter

Passar `pf.storage_key` e usar o novo contrato:

```python
# Só chama rag_service se houve ingestão (status != pending)
# e se a chave foi salva (storage_key não vazio — ingest pode ter falhado antes do "done")
if pf.status != "pending" and pf.storage_key:
    try:
        await adapter.delete_file(
            file_id=pf.id,
            storage_key=pf.storage_key,
        )
    except Exception as e:
        logger.warning("Erro ao remover arquivo do rag_service (best-effort): %s", e)
```

Se `pf.storage_key` estiver vazio (ingestão falhou antes do evento `"done"`), o
bloco é pulado — o arquivo nunca chegou ao MinIO nem ao Qdrant, então não há nada
a limpar.

**Dependências:** Fix2-3.

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|---|---|---|
| `storage_key` vazio em arquivo com `status=error` | Média — falha antes do evento `"done"` | Guard `if pf.storage_key` em Fix2-4 |
| Qdrant com chunks órfãos de arquivos deletados antes da correção | Alta — bug pré-existente | Botão de reprocessar na UI já força nova indexação; chunks antigos são filtrados por `file_id` inexistente no banco |
| Chunk de Qdrant não removido se `delete_file_chunks` falhar | Baixa | Try/except com warning — a deleção do MinIO ainda prossegue |

---

## Critérios de Conclusão

**Fix 1 — Fila de ingestão:**
- [ ] Upload de 6 arquivos simultâneos: apenas 1 em `"processing"`, os demais com `"Xª na fila"`
- [ ] A posição decrementa corretamente a cada arquivo concluído
- [ ] `chunks_done` final bate com o número reportado durante o progresso
- [ ] `reprocessar` também entra na fila (não pula à frente dos pending)

**Fix 2 — Deleção:**
- [ ] Após excluir um arquivo com status `ready`, o objeto some do MinIO (verificar via console MinIO)
- [ ] Chunks do arquivo deletado não aparecem em buscas subsequentes
- [ ] Excluir arquivo com status `error` (storage_key vazio) não gera erro 500

**Geral:**
- [ ] `uv run ruff check .` → 0 erros
- [ ] `uv run pytest tests/` → todos passando
- [ ] `npm run build` → sem erros de tipo
