# Relatório de Qualidade de Código
**Data:** 2026-04-04
**Escopo:** Mudanças da feature `feat-rag-stem-subagent` (Fases 1, 2 e 3)

Arquivos novos:
- `src/domain/tools/research_project_knowledge.py`
- `src/prompts/rag_research_agent_prompt.md`
- `src/skills/rag_research.md`

Arquivos modificados:
- `src/domain/tools/factory.py`
- `src/infrastructure/rag_adapter.py`
- `src/ports/rag_port.py`
- `rag_service/main.py`
- `rag_service/pipelines.py`
- `rag_service/pyproject.toml`

---

### Lint (Ruff)

Nenhum problema encontrado. `uv run ruff check .` → 0 erros.

---

### TypeScript (tsc)

Nenhum problema encontrado. `npm run build` → ✓ built sem erros de tipo.
(Aviso pré-existente de chunk size > 500 kB — não relacionado às mudanças.)

---

### Testes

637 passed in 22.98s — nenhuma regressão.

---

### Arquitetura

Nenhum problema encontrado.

- `src/domain/` não importa de `backend/`, `application/` ou `infrastructure/` ✅
- `research_project_knowledge.py` usa `state.rag` (RagPort injetado) — zero import de infra ✅
- `state.chat_model_factory` usado com guard correto ✅
- Novo endpoint `/search/stems` usa `Depends(_require_secret)` ✅
- `response_model` declarado em todos os novos endpoints ✅
- `project_id` e `file_id` são `str` em `rag_service/` ✅

---

### Estilo Python

#### Tamanho e complexidade

- [AVISO] `src/domain/tools/research_project_knowledge.py:59` — `make_research_project_knowledge` com 144 linhas (máx 40). Closures aninhados — padrão herdado de `research_topic.py` (159 linhas).
- [AVISO] `src/domain/tools/research_project_knowledge.py:64` — `research_project_knowledge` (tool interna) com 137 linhas (máx 40).
- [AVISO] `rag_service/pipelines.py:219` — `search_by_stems` com 74 linhas (máx 40). Candidata a ser dividida em `_build_stem_filter()` + `_scroll_stems()`.
- [AVISO] `rag_service/pipelines.py` — arquivo com 348 linhas (máx 300). Candidato a split em `pipelines_ingest.py` / `pipelines_search.py`.
- [AVISO] `rag_service/main.py` — arquivo com 302 linhas (máx 300). Ultrapassou por 2 linhas.
- [AVISO] `src/domain/tools/research_project_knowledge.py:59` — aninhamento 4 níveis (máx 3): factory → tool → closures → try/except.
- [AVISO] `rag_service/pipelines.py:51` — `_stem_text` aninhamento 4 níveis (máx 3): try → except LookupError → try (download) → except Exception.

#### Type hints

- [AVISO] `src/domain/tools/research_project_knowledge.py:59` — `make_research_project_knowledge` sem anotação de retorno (deveria ser `-> Callable`). Mesmo padrão omitido em `research_topic.py` (pré-existente).
- [AVISO] `rag_service/pipelines.py:121` — `ingest_file_stream` sem anotação de retorno. Deveria ser `-> Generator[dict[str, Any], None, None]`. Problema pré-existente.

#### Lógica e segurança de runtime

- [AVISO] `rag_service/pipelines.py:72` — `_stem_text` usa recursão sem limite de profundidade no caminho de auto-download do corpus NLTK. Se `nltk.download` retornar sem erro mas o corpus ainda falhar, ocorre `RecursionError`. Mitigação: usar flag de tentativa única antes do retry.

- [AVISO] `rag_service/pipelines.py:251` — `search_by_stems` instancia `QdrantClient(url=...)` a cada chamada (sem cache). Em alta frequência cria nova conexão TCP por busca. Mitigação: singleton `_qdrant_client: QdrantClient | None = None` igual ao padrão de `_RERANKER`.

#### Tratamento de erros

- [AVISO] `src/infrastructure/rag_adapter.py:128` — `except Exception: pass` sem log no `reprocess_streaming`. **Pré-existente**, não introduzido pelas mudanças.

Todos os `except Exception` nos novos arquivos têm `logger.warning`/`logger.error` ou `return` descritivo ✅.

---

### Estilo TypeScript / React

Não aplicável — nenhum arquivo frontend foi modificado.

---

### Segurança

- [SUGESTÃO] `rag_service/main.py:1` — docstring do módulo não lista o endpoint `/search/stems` na tabela de endpoints do cabeçalho.

Nenhum token, senha ou dado sensível logado ✅.
Endpoint `/search/stems` exige `Depends(_require_secret)` ✅.
Nenhuma variável de ambiente secreta com default hardcoded ✅.

---

### Resumo

| Severidade | Total | Novos | Pré-existentes |
|---|---|---|---|
| **Erros** | 0 | 0 | 0 |
| **Avisos** | 11 | 9 | 2 |
| **Sugestões** | 1 | 1 | 0 |

**Avisos novos por prioridade:**

| Prioridade | Arquivo | Linha | Descrição |
|---|---|---|---|
| 🔴 Alta | `pipelines.py` | 72 | Recursão sem limite em `_stem_text` (risco de RecursionError em produção) |
| 🔴 Alta | `pipelines.py` | 251 | `QdrantClient` sem cache — nova conexão TCP por busca |
| 🟡 Média | `pipelines.py` | — | Arquivo com 348 linhas (máx 300) |
| 🟡 Média | `main.py` | — | Arquivo com 302 linhas (máx 300) |
| 🟡 Média | `pipelines.py` | 219 | `search_by_stems` com 74 linhas (máx 40) |
| 🟡 Média | `pipelines.py` | 51 | `_stem_text` aninhamento 4 níveis (máx 3) |
| 🟢 Baixa | `research_project_knowledge.py` | 59 | `make_research_project_knowledge` sem anotação de retorno |
| 🟢 Baixa | `research_project_knowledge.py` | 59 | Funções com 137–144 linhas (padrão herdado do projeto) |
| 🟢 Baixa | `research_project_knowledge.py` | 59 | Aninhamento 4 níveis (padrão herdado) |

**Próximo passo sugerido:** Corrigir os 2 avisos de Alta prioridade em `pipelines.py` — recursão em `_stem_text` e cache de `QdrantClient` — antes do deploy em produção. Os demais (tamanho/complexidade) podem ser endereçados em refatoração posterior.

---
_Relatório salvo em: `.pi/audit/2026-04-04-feat-rag-stem-subagent.md`_
