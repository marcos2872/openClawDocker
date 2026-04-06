# Relatório de Qualidade de Código
**Data:** 2026-04-03  
**Escopo:** Repositório completo  
**Ferramentas:** ruff, tsc + vite build, pytest  

---

## Resumo Executivo

| Categoria | Erros | Avisos | Sugestões |
|---|---|---|---|
| Arquitetura / Camadas | 20 | 0 | 0 |
| Linter Python (ruff) | 3 | 90 | 0 |
| TypeScript / Build | 0 | 1 | 1 |
| Testes automatizados | 104 falhas de ambiente | 0 | 0 |
| Tamanho de arquivos | 0 | 16 | 0 |
| Tratamento de erros | 0 | 2 | 0 |
| Produção segura | 0 | 0 | 0 |

**Total: 533 testes passam · 104 erros de ambiente · build TS ok · ruff 93 problemas**

---

## 1. Linters Automáticos

### 1.1 Ruff — Python

**Resultado:** 93 erros (59 auto-corrigíveis com `ruff check --fix`)

#### Erros críticos (não auto-corrigíveis)

- [ERRO] `src/domain/tools/render_pptx.py:217` — **F821** Nome indefinido `PptxRegistrar` usado em type hint string. O tipo é referenciado mas nunca importado ou definido no módulo.

#### Avisos — Imports não utilizados (F401) — amostra representativa

- [AVISO] `backend/auth/deps.py:7` — `sqlmodel.select` importado mas não usado
- [AVISO] `backend/main.py:35` — `pydantic.BaseModel` importado mas não usado
- [AVISO] `backend/routers/templates_setup.py:12` — `pathlib.Path` importado mas não usado
- [AVISO] `backend/routers/templates_setup.py:21` — `get_current_user` importado mas não usado
- [AVISO] `backend/migrations/versions/712d87419fc3_initial_schema.py:13` — `sqlalchemy` importado mas não usado
- [AVISO] `src/domain/schema_builder.py:16` — `pathlib.Path` importado mas não usado
- [AVISO] `src/infrastructure/_table_renderer.py:16` — `TableType` importado mas não usado
- [AVISO] `src/infrastructure/_table_renderer.py:18` — `NULL_VALUE` importado mas não usado
- [AVISO] `src/infrastructure/azure_client.py:15` — `LLMPort` importado mas não usado (idem openai_client, google_client, openai_compatible_client, copilot_client)
- [AVISO] `src/infrastructure/pptx_renderer.py:33` — `coerce` importado mas não usado
- [AVISO] `src/infrastructure/minio_client.py:33` — `boto3` importado mas não usado (TYPE_CHECKING block)
- [AVISO] `src/infrastructure/copilot_responses_client.py:33` — `BaseTool` importado mas não usado
- [AVISO] Múltiplos arquivos em `tests/` — `pytest` importado mas não usado (20+ ocorrências)
- [AVISO] `tests/domain/test_extractor.py:388` — **F841** variável `cell` atribuída mas nunca usada
- [AVISO] `tests/domain/test_tools_create_template.py:222` — **F841** variável `pptx_path` atribuída mas nunca usada
- [AVISO] `tests/domain/test_tools_setup_template.py:19` — **F841** variável `slide` atribuída mas nunca usada
- [AVISO] `tests/infrastructure/test_local_artifact_store.py:190` — **F841** variável `result` atribuída mas nunca usada

#### Avisos — Imports fora do topo do arquivo (E402)

- [AVISO] `backend/main.py:23–51` — Bloco inteiro de imports após `load_dotenv()` no meio do arquivo. O padrão correto é mover `load_dotenv()` para um bloco `__init__` ou usar variável de ambiente antes dos imports.
- [AVISO] `tests/backend/conftest.py:29–51` — Imports após manipulação de módulo (monkey-patch de `_ENDPOINT`). Causa ruído de linter mas é intencional para mock; deveria usar `# noqa: E402`.

#### F-strings sem placeholder (F541)

- [AVISO] `.opencode/skills/excalidraw/references/render_excalidraw.py:124` — `f"ERROR: ..."` sem `{}`. Remover prefixo `f`.
- [AVISO] `backend/routers/auth_github.py:314` — `f"Cria uma conta..."` sem `{}`. Remover prefixo `f`.

### 1.2 TypeScript / Vite Build

**Resultado:** ✅ Build passou sem erros de tipo.

- [SUGESTÃO] Bundle JS principal (`index-BsA-Hp2j.js`) tem **512 KB** minificado (151 KB gzip). Vite emite aviso de chunks > 500 KB. Considerar `dynamic import()` para rotas pesadas (ex.: editor de slides, admin).

### 1.3 Pytest

**Resultado:** 533 passaram · **104 ERRORs** — todos em `tests/backend/`

- [AVISO] `tests/backend/test_routes.py` e `tests/backend/test_pptx_routes.py` — Todos os testes falham com:
  ```
  sqlalchemy.exc.OperationalError: password authentication failed for user "dummy"
  ```
  O `conftest.py` tenta substituir a engine por SQLite, mas a engine Postgres do `backend/db.py` é instanciada no import antes do mock ser aplicado. **Causa: ordem de import no conftest não isola corretamente o banco.** Não é falha de lógica de negócio, mas impede validação automatizada do backend em CI.

---

## 2. Arquitetura / Separação de Camadas

### 2.1 Violações em `src/domain/tools/` — CRÍTICO

`src/domain/` **nunca deve importar** de `src/application/` ou `src/infrastructure/` (regra explícita do AGENTS.md). Os arquivos abaixo fazem isso via **imports lazy dentro de funções**, o que não elimina a violação arquitetural:

- [ERRO] `src/domain/tools/_helpers.py:59` — `from src.application.schema_enricher import enrich_if_available`
- [ERRO] `src/domain/tools/generate_fields.py:36` — `from src.application.json_parser import extract_json`
- [ERRO] `src/domain/tools/create_template.py:96` — `from src.infrastructure.artifact_store import …`
- [ERRO] `src/domain/tools/create_template.py:145` — `from src.infrastructure.minio_client import …`
- [ERRO] `src/domain/tools/create_template.py:222` — `from src.infrastructure.artifact_store import …`
- [ERRO] `src/domain/tools/create_template.py:226` — `from src.infrastructure.minio_client import …`
- [ERRO] `src/domain/tools/generate_fields.py:49` — `from src.infrastructure.artifact_store import …`
- [ERRO] `src/domain/tools/list_templates.py:31` — `from src.infrastructure.artifact_store import …`
- [ERRO] `src/domain/tools/load_creation_skill.py:87` — `from src.infrastructure.artifact_store import find_template_skill`
- [ERRO] `src/domain/tools/load_schema.py:35` — `from src.infrastructure.artifact_store import …`
- [ERRO] `src/domain/tools/read_pptx.py:144` — `from src.infrastructure.artifact_store import find_template`
- [ERRO] `src/domain/tools/render_pptx.py:42` — `from src.infrastructure.pptx_renderer import render`
- [ERRO] `src/domain/tools/render_pptx.py:51` — `from src.infrastructure.artifact_store import …`
- [ERRO] `src/domain/tools/render_pptx.py:162` — `from src.infrastructure.minio_client import …`
- [ERRO] `src/domain/tools/render_pptx.py:205` — `from src.infrastructure.minio_client import …`
- [ERRO] `src/domain/tools/setup_template.py:37` — `from src.infrastructure.artifact_store import …`
- [ERRO] `src/domain/tools/validate_all.py:37` — `from src.infrastructure.artifact_store import …`
- [ERRO] `src/domain/tools/research_topic.py:124` — `from src.infrastructure.langchain_factory import create_chat_model`
- [ERRO] `src/domain/tools/search_project_knowledge.py:55` — `from src.infrastructure.rag_adapter import RagAdapter`

**Correção recomendada:** As tools precisam receber suas dependências via injeção (ports/protocolos passados como parâmetros ou via `SessionState`), não importando concretamente de `infrastructure/`. Criar ports (`ArtifactStorePort`, `PptxRendererPort`) em `src/ports/` e injetá-los via `SessionState` ou factory.

### 2.2 Conformidade das demais camadas

- `src/application/` → não importa de `backend/` ✅
- `backend/` → usa apenas `application/` e `infrastructure/` ✅
- `src/domain/` (fora de `tools/`) → não viola ✅

---

## 3. Regras do Backend

### 3.1 Autenticação nas rotas

- `Depends(require_admin)` aplicado em rotas admin ✅
- `Depends(get_current_user)` aplicado em rotas de usuário ✅
- `decrypt_token()` chamado antes do uso de tokens Copilot ✅

### 3.2 Event loop / SSE

- Operações síncronas bloqueantes usam `loop.run_in_executor(None, fn)` ✅
- SSE usa `EventSourceResponse` de `sse-starlette` ✅
- `delete_setup_session()` chamado ao finalizar/cancelar sessões de setup ✅

### 3.3 `response_model` nas rotas

- [AVISO] Algumas rotas usam `response_model=dict[str, str]` ou `response_model=dict[str, bool]` — tecnicamente declarado, mas sem schema tipado. Preferível criar `Pydantic` schemas específicos para cada resposta, facilitando validação e documentação OpenAPI.

---

## 4. Regras do Frontend

- Componentes não chamam `fetch` diretamente ✅ (os `refetch` encontrados são de hooks internos de `react-query`)
- `EventSource` não utilizado — SSE via `fetch + ReadableStream` ✅
- `AbortController` presente em todos os `useEffect` com SSE ✅
- Estado derivado não armazenado em `useState` desnecessariamente ✅

### 4.1 Tamanho de componentes (> 200 linhas)

- [AVISO] `frontend/src/components/TemplateCard.tsx` — **450 linhas** (limite: 200)
- [AVISO] `frontend/src/components/SetupWizard.tsx` — **279 linhas** (limite: 200)
- [AVISO] `frontend/src/pages/Admin.tsx` — **254 linhas** (limite: 200)
- [AVISO] `frontend/src/components/ChatWindow.tsx` — **247 linhas** (limite: 200)
- [AVISO] `frontend/src/pages/Files.tsx` — **212 linhas** (limite: 200)

---

## 5. Estilo Python — Tamanho de Arquivos (> 300 linhas)

- [AVISO] `backend/routers/chat.py` — **698 linhas**
- [AVISO] `backend/routers/templates_crud.py` — **694 linhas**
- [AVISO] `src/infrastructure/copilot_responses_client.py` — **496 linhas**
- [AVISO] `src/infrastructure/copilot_anthropic_client.py` — **449 linhas**
- [AVISO] `backend/routers/templates_setup.py` — **442 linhas**
- [AVISO] `backend/routers/auth_github.py` — **434 linhas**
- [AVISO] `backend/routers/admin.py` — **427 linhas**
- [AVISO] `backend/routers/pptx.py` — **404 linhas**
- [AVISO] `src/application/schema_enricher.py` — **379 linhas**
- [AVISO] `src/infrastructure/langchain_factory.py` — **373 linhas**
- [AVISO] `backend/routers/project_files.py` — **372 linhas**
- [AVISO] `src/infrastructure/_table_renderer.py` — **371 linhas**
- [AVISO] `src/infrastructure/template_store.py` — **343 linhas**
- [AVISO] `src/infrastructure/minio_client.py` — **338 linhas**
- [AVISO] `src/application/agent_service.py` — **307 linhas**
- [AVISO] `src/infrastructure/_text_renderer.py` — **302 linhas**

---

## 6. Tratamento de Erros

- [AVISO] `src/application/schema_enricher.py:362` — `except Exception:` silencia exceção sem log ao carregar `prompts_cfg`. Ainda que seja tolerável como fallback, adicionar `logger.debug(exc)` para rastreabilidade.
- [AVISO] `src/application/agent_service.py:245` — `except Exception: … raise` é OK (re-raise). Sem problema.

---

## 7. Outros

- Uso de `os.path` — Nenhum encontrado ✅
- Pydantic v1 APIs (`.dict()`, `.schema()`, `@validator`) — Nenhum encontrado ✅
- `Optional[X]`, `Union[X,Y]`, `List[X]` de `typing` — Nenhum encontrado ✅
- `sys.exit()` fora de CLI — Nenhum encontrado ✅
- `print()` em código de produção — `src/application/agent_service.py:74` está **dentro de docstring** (exemplo de uso), não é código executável ✅

---

## Plano de Ação Prioritário

| Prioridade | Item | Esforço |
|---|---|---|
| 🔴 Alta | Corrigir violações de camada em `src/domain/tools/` (criar ports, injetar via SessionState) | Alto |
| 🔴 Alta | Corrigir F821 (`PptxRegistrar` indefinido em `render_pptx.py:217`) | Baixo |
| 🟡 Média | Corrigir 104 erros de setup dos testes backend (isolamento de DB no conftest) | Médio |
| 🟡 Média | Executar `ruff check --fix .` para auto-corrigir 59 problemas F401/F541/F841 | Baixo |
| 🟡 Média | Corrigir E402 em `backend/main.py` (mover `load_dotenv()` para antes dos imports ou reorganizar) | Baixo |
| 🟢 Baixa | Quebrar arquivos com > 300 linhas (especialmente routers) | Alto |
| 🟢 Baixa | Quebrar componentes React com > 200 linhas | Médio |
| 🟢 Baixa | Criar schemas Pydantic para rotas que retornam `dict[str, str]` | Médio |
| 🟢 Baixa | Code splitting no frontend (bundle > 500 KB) | Médio |

