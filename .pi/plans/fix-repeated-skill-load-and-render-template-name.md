# Plano: Corrigir re-carregamento de skill e nome errado no render_pptx

**Data:** 2026-04-04
**Autor:** agente-plan
**Status:** aprovado

---

## Objetivo

Corrigir dois bugs no fluxo de criação de PPTX via agente:

1. `load_creation_skill` é chamada repetidamente a cada turno, re-emitindo o evento SSE
   de "skill carregada" e reinjetando o conteúdo da skill no contexto do LLM.

2. `render_pptx("fapi")` falha porque o LLM usa o nome genérico/curto em vez do nome
   exato do template (ex: "fapi-040426_0054"). Sem fallback para `state.template_name`,
   o arquivo não é encontrado e os campos preenchidos não são localizados.

---

## Arquivos Afetados

| Arquivo | Ação | Motivo |
|---|---|---|
| `src/domain/tools/session.py` | modificar | Adicionar `_loaded_skill_names: set[str]` para rastrear skills já carregadas |
| `src/domain/tools/load_creation_skill.py` | modificar | Guard contra re-carregamento usando `_loaded_skill_names`; marcar skill após emissão |
| `src/domain/tools/render_pptx.py` | modificar | Fallback para `state.template_name` quando nome explícito não resolve |
| `src/prompts/agent_system_prompt.md` | modificar | Clarificar que list_templates + load_creation_skill são chamadas UMA vez |

---

## Sequência de Execução

### Passo 1 — `session.py`: adicionar `_loaded_skill_names`

Adicionar logo após `self.rag`:

```python
        # Conjunto de skills já carregadas nesta sessão (evita re-emissão e re-carregamento)
        self._loaded_skill_names: set[str] = set()
```

### Passo 2 — `load_creation_skill.py`: guard de re-carregamento

Após derivar `base` do nome do template, antes de chamar `find_template_skill_fn`:

```python
            # Guard: evita recarregar e re-emitir se a skill já foi carregada nesta sessão
            skill_key = f"{base}-skill" if base else "pptx_creation"
            if skill_key in state._loaded_skill_names:
                return (
                    f"Skill do template '{base or 'global'}' já está ativa para esta sessão. "
                    "Continue com o preenchimento ou validação dos campos."
                )
```

E após `state.emit_skill(...)`, marcar a skill como carregada:

```python
        state._loaded_skill_names.add(skill_key)
```

### Passo 3 — `render_pptx.py`: fallback para `state.template_name`

Substituir o bloco `find_template` por versão com fallback:

```python
        resolved_name = template_name
        try:
            pptx_path = store.find_template(template_name)
        except FileNotFoundError:
            # Fallback: usa state.template_name quando o LLM passa nome genérico/errado
            if state.template_name and state.template_name != template_name:
                try:
                    pptx_path = store.find_template(state.template_name)
                    resolved_name = state.template_name
                except FileNotFoundError as e:
                    return f"Erro: {e}"
            else:
                return f"Erro: template '{template_name}' não encontrado."

        # base_name derivado do nome que realmente resolveu
        base = base_name(resolved_name)
```

### Passo 4 — `agent_system_prompt.md`: clarificar chamadas únicas

Na seção GERAÇÃO DE APRESENTAÇÕES PPTX, adicionar nota após passo 2:

```markdown
   > **Importante:** `list_templates()` e `load_creation_skill()` são chamadas
   > **uma única vez** no início do fluxo. Nas mensagens seguintes, os campos
   > já estão carregados — vá direto para `get_filled_fields()` ou `fill_fields_batch()`.
```

---

## Critérios de Conclusão

- [ ] `uv run ruff check .` → 0 erros
- [ ] `uv run pytest tests/` → todos passando
- [ ] Em sessão de teste, `load_creation_skill` aparece apenas 1x no SSE de eventos
- [ ] `render_pptx("fapi")` encontra "fapi-040426_0054-template.pptx" via fallback
