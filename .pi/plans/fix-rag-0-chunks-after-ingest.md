# Plano: Corrigir 0 chunks após ingestão RAG

**Data:** 2026-04-05  
**Autor:** agente-plan  
**Status:** aprovado

---

## Diagnóstico

### Sintoma
Após upload de um arquivo (ex.: PDF com 28 chunks), o frontend exibe:
```
Pronto · 0 chunks
```
mesmo que durante o processamento o log/UI mostre `total=28`.

### Rastreamento do fluxo
```
upload_project_file
  → store_file (POST /store → MinIO)
  → BackgroundTask: _reprocess_background
      → adapter.reprocess_streaming  (POST /reprocess)
          → rag_service /reprocess
              → delete_file_chunks  (remove chunks antigos)
              → make_ingest_stream  (thread via iter_sync_gen)
                  → ingest_file_stream
                      → _build_chunks → 28 chunks ✓
                      → yield {"type": "start", "total": 28} ✓
                      → loop 28×:
                          embedder.run([chunk])   ← FALHA AQUI?
                          writer.run(embedded)    ← OU AQUI?
                          except Exception → logger.WARNING (swallowed!)
                          yield {"type": "progress", ...} ✓  ← por isso o UI vê 28
                      → yield {"type": "done", "chunks_indexed": 0}  ← bug!
      ← _run_ingest_stream recebe done(chunks_indexed=0)
          → _update_file(status="ready", chunks_done=0, chunks_total=0)
```

### Bug 1 — Exceções silenciosas em `ingest_file_stream` (rag_service)

Em `rag_service/pipelines.py`, o `except` da linha ~211 captura **qualquer** exceção
(Ollama connection refused, model not found, Qdrant rejeitou upsert, etc.),
loga em **WARNING** (sem stack trace) e continua o loop — `written` permanece 0.

As 28 iterações do progresso ainda são emitidas (o `yield progress` fica **fora** do
try-except), portanto o UI sempre vê "28 chunks sendo processados".

Ao final: `yield {"type": "done", "chunks_indexed": 0}` → o backend interpreta isso
como sucesso com 0 chunks.

**Causas mais prováveis de a exceção ser lançada em TODOS os chunks:**
- Modelo Ollama (`qwen3-embedding:8b`) não está carregado/baixado
- Qdrant inacessível ou coleção não criada (a `_initialize_client()` + `_set_up_collection()`
  é lazy — só roda no primeiro `writer.run()`, podendo falhar silenciosamente)
- Qdrant rejeitou o upsert (dimensão errada, etc.)

### Bug 2 — `_run_ingest_stream` não distingue "sucesso com 0 chunks" de "falha total"

Em `backend/routers/project_files.py`, `_run_ingest_stream` ao receber
`{"type": "done", "chunks_indexed": 0}` define `status="ready"` incondicionalmente.
O arquivo aparece como **"Pronto · 0 chunks"** em vez de **"Erro"**, mascarando a falha.

---

## Escopo

**Dentro do escopo:**
- Melhorar observabilidade na camada de embedding (log ERROR + traceback)
- Emitir evento `error` quando `written==0` e `total>0`
- Fazer `_run_ingest_stream` respeitar o evento `error` e não sobrescrever `status="error"` com `status="ready"`
- Garantir que o `done` sempre seja emitido ao final (o backend usa para fechar o fluxo)

**Fora do escopo:**
- Diagnóstico da causa raiz de infraestrutura (Ollama/Qdrant down) — é problema de deploy
- Retry automático de chunks com falha
- Health-check de Ollama/Qdrant no startup do rag_service

---

## Arquivos Afetados

| Arquivo | Ação | Motivo |
|---|---|---|
| `rag_service/pipelines.py` | modificar | Melhorar logging + emitir `error` quando todos chunks falham |
| `backend/routers/project_files.py` | modificar | `_run_ingest_stream`: não sobrescrever `status=error` com `status=ready` |

---

## Sequência de Execução

### 1. `rag_service/pipelines.py` — `ingest_file_stream`

**Arquivo:** `rag_service/pipelines.py`

**O que mudar:**

```python
# ANTES
written = 0
for i, chunk in enumerate(chunks):
    try:
        embed_result = embedder.run([chunk])
        embedded = embed_result.get("documents", [])
        if embedded:
            writer.run(documents=embedded)
            written += 1
    except Exception as e:
        logger.warning(
            "Erro ao embedar chunk %d/%d de '%s': %s",
            i + 1,
            total,
            file_path.name,
            e,
        )

    yield {"type": "progress", "done": i + 1, "total": total}

yield {"type": "done", "chunks_indexed": written}
logger.info("Indexados %d/%d chunks de '%s'", written, total, file_path.name)
```

```python
# DEPOIS
written = 0
last_error: Exception | None = None
for i, chunk in enumerate(chunks):
    try:
        embed_result = embedder.run([chunk])
        embedded = embed_result.get("documents", [])
        if embedded:
            writer.run(documents=embedded)
            written += 1
    except Exception as e:
        last_error = e
        logger.error(
            "Erro ao embedar chunk %d/%d de '%s': %s",
            i + 1,
            total,
            file_path.name,
            e,
            exc_info=True,  # inclui stack trace no log
        )

    yield {"type": "progress", "done": i + 1, "total": total}

# Se TODOS os chunks falharam, emite evento de erro com a última exceção
if written == 0 and total > 0:
    error_msg = str(last_error) if last_error else "Falha desconhecida ao indexar os chunks."
    logger.error(
        "Nenhum chunk foi indexado de '%s' (%d falhas). Verifique Ollama e Qdrant.",
        file_path.name,
        total,
    )
    yield {"type": "error", "message": f"Nenhum chunk foi indexado: {error_msg}"}

# Sempre emite done para fechar o stream no backend
yield {"type": "done", "chunks_indexed": written}
logger.info("Indexados %d/%d chunks de '%s'", written, total, file_path.name)
```

**Dependências:** nenhuma (mudança isolada).

---

### 2. `backend/routers/project_files.py` — `_run_ingest_stream`

**Arquivo:** `backend/routers/project_files.py`

**O que mudar:** adicionar flag `seen_error` para que o evento `done` não sobrescreva
`status="error"` definido por um evento `error` anterior.

```python
# ANTES
async def _run_ingest_stream(stream, file_id: str, engine) -> None:
    _update_file(engine, file_id, status="processing")

    try:
        async for event in stream:
            etype = event.get("type")

            if etype == "start":
                _update_file(engine, file_id, chunks_total=event.get("total"))

            elif etype == "progress":
                _update_file(
                    engine,
                    file_id,
                    chunks_done=event.get("done"),
                    chunks_total=event.get("total"),
                )

            elif etype == "done":
                indexed = event.get("chunks_indexed", 0)
                _update_file(
                    engine,
                    file_id,
                    status="ready",
                    chunks_done=indexed,
                    chunks_total=indexed,
                )
                logger.info("Ingestão concluída: file_id=%s, chunks=%d", file_id, indexed)

            elif etype == "error":
                msg = event.get("message", "Erro desconhecido no rag_service")
                _update_file(engine, file_id, status="error", error_message=msg[:500])
                logger.error("Falha na ingestão do file_id=%s: %s", file_id, msg)

    except Exception as e:
        logger.error("Falha inesperada na ingestão do file_id=%s: %s", file_id, e)
        _update_file(engine, file_id, status="error", error_message=str(e)[:500])
```

```python
# DEPOIS
async def _run_ingest_stream(stream, file_id: str, engine) -> None:
    _update_file(engine, file_id, status="processing")
    seen_error = False  # ← flag: se error event foi recebido, done não redefine status

    try:
        async for event in stream:
            etype = event.get("type")

            if etype == "start":
                _update_file(engine, file_id, chunks_total=event.get("total"))

            elif etype == "progress":
                _update_file(
                    engine,
                    file_id,
                    chunks_done=event.get("done"),
                    chunks_total=event.get("total"),
                )

            elif etype == "done":
                indexed = event.get("chunks_indexed", 0)
                if seen_error:
                    # Mantém status=error; apenas registra contagens para contexto
                    _update_file(engine, file_id, chunks_done=indexed, chunks_total=indexed)
                else:
                    _update_file(
                        engine,
                        file_id,
                        status="ready",
                        chunks_done=indexed,
                        chunks_total=indexed,
                    )
                logger.info("Ingestão concluída: file_id=%s, chunks=%d", file_id, indexed)

            elif etype == "error":
                seen_error = True
                msg = event.get("message", "Erro desconhecido no rag_service")
                _update_file(engine, file_id, status="error", error_message=msg[:500])
                logger.error("Falha na ingestão do file_id=%s: %s", file_id, msg)

    except Exception as e:
        logger.error("Falha inesperada na ingestão do file_id=%s: %s", file_id, e)
        _update_file(engine, file_id, status="error", error_message=str(e)[:500])
```

**Dependências:** nenhuma (mudança isolada, não depende do passo 1).

---

## Por que estes dois passos são necessários?

| Cenário | Fix 1 sozinho | Fix 2 sozinho | Ambos |
|---|---|---|---|
| Todos 28 falham → `error` + `done(0)` emitidos | `error` emitido ✓ | `done(0)` não sobrescreve ✓ | ✓ status="error" com msg |
| Todos 28 falham (versão antiga sem Fix 1) | — | `done(0)` → "Pronto · 0 chunks" | ✓ status="error" genérico |
| Arquivo genuinamente vazio (0 chunks extraídos) | sem `error` event ✓ | `seen_error=False` → "ready" ✓ | ✓ correto |
| Sucesso parcial (10/28) | sem `error` event ✓ | `seen_error=False` → "ready" ✓ | ✓ correto |

---

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|---|---|---|
| `error` + `done` emitidos em sequência → comportamento de `seen_error` | baixa | Fix 2 trata exatamente isso |
| Arquivo com 0 chunks válidos (ex.: PDF escaneado sem OCR) marcado como erro | não ocorre | erro só emitido quando `total>0` AND `written==0` |
| ruff reclamar de `last_error: Exception \| None = None` | baixa | tipo compatível com Python 3.10+ |

---

## O que NÃO resolve (causa raiz)

Este plano **não corrige** a causa raiz de infraestrutura. Após aplicar o fix, o arquivo
vai mostrar **"Erro"** com uma mensagem como:

```
Nenhum chunk foi indexado: HTTPConnectionPool(host='ollama', port=11434): Max retries exceeded...
```

ou

```
Nenhum chunk foi indexado: Collection 'knowledge_<id>' doesn't exist
```

Com essa mensagem visível no frontend, fica fácil identificar se o problema é:
- **Ollama fora do ar** → subir o serviço e fazer `ollama pull qwen3-embedding:8b`
- **Qdrant fora do ar** → verificar container `qdrant`
- **Outro** → ver stack trace nos logs do `rag_service`

---

## Critérios de Conclusão

- [ ] Upload de arquivo com Ollama/Qdrant problemático mostra badge **"Erro"** com mensagem útil
- [ ] Upload de arquivo com infraestrutura saudável → badge **"Pronto · N chunks"** (comportamento inalterado)
- [ ] Logs do `rag_service` mostram `ERROR` com stack trace para cada chunk que falhou
- [ ] `uv run ruff check .` → 0 erros
- [ ] `uv run pytest tests/` → todos passando
