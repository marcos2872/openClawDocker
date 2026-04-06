# Plano: Fix rota `/chat` inexistente — Opção B (sessões sempre dentro de projeto)

**Data:** 2026-04-05
**Autor:** agente-plan
**Status:** aprovado

---

## Objetivo

Corrigir os 4 pontos do frontend que navegam para `/chat` (rota inexistente no router).
Na Opção B, sessões de chat deixam de existir de forma standalone: ao clicar
"Usar template" em `TemplatesPage`, o usuário escolhe (ou cria) um projeto antes de
iniciar a conversa — e é redirecionado para `/projects/:id` onde o chat já vive.
`Login.tsx` e `Admin.tsx` simplesmente passam a apontar para `/`.

---

## Escopo

**Dentro do escopo:**
- Corrigir `Login.tsx` (2 ocorrências de `/chat` → `/`)
- Corrigir `Admin.tsx` (1 ocorrência de `/chat` → `/`)
- Criar `ProjectSelectorModal.tsx` — modal para selecionar ou criar projeto
- Atualizar `Templates.tsx` — `handleSelect` abre o modal antes de criar a sessão
- Remover a prop `initialSessionId` de `ChatPage` (não há mais rota que a use)

**Fora do escopo:**
- Mudanças no backend
- Mudanças em `ProjectDetailPage` (já funciona corretamente)
- Mudanças nos hooks `useChat`, `useProjects` etc.
- Rota `/chat` standalone (Opção A)

---

## Arquivos Afetados

| Arquivo | Ação | Motivo |
|---|---|---|
| `frontend/src/pages/Login.tsx` | modificar | Trocar 2× `/chat` por `/` |
| `frontend/src/pages/Admin.tsx` | modificar | Trocar 1× `/chat` por `/` |
| `frontend/src/pages/Templates.tsx` | modificar | `handleSelect` → abre `ProjectSelectorModal` |
| `frontend/src/pages/Chat.tsx` | modificar | Remover prop `initialSessionId` (não tem mais consumidor) |
| `frontend/src/components/ProjectSelectorModal.tsx` | criar | Modal de seleção/criação de projeto |

---

## Sequência de Execução

### 1. Corrigir `Login.tsx`

**Arquivo:** `frontend/src/pages/Login.tsx`

Duas trocas independentes:

```diff
- if (user) return <Navigate to="/chat" replace />;
+ if (user) return <Navigate to="/" replace />;
```

```diff
- navigate("/chat", { replace: true });
+ navigate("/", { replace: true });
```

**Dependências:** nenhuma.

---

### 2. Corrigir `Admin.tsx`

**Arquivo:** `frontend/src/pages/Admin.tsx`

```diff
- return <Navigate to="/chat" replace />;
+ return <Navigate to="/" replace />;
```

**Dependências:** nenhuma.

---

### 3. Criar `ProjectSelectorModal.tsx`

**Arquivo:** `frontend/src/components/ProjectSelectorModal.tsx`

Modal com dois modos internos: `selecting` e `creating`.

**Props:**
```typescript
interface ProjectSelectorModalProps {
  templateName: string;
  onCancel: () => void;
}
// Não precisa de onDone — navega internamente via useNavigate
```

**Comportamento:**

**Modo `selecting`** (padrão):
- Busca `listProjects()` ao montar (spinner enquanto carrega).
- Lista projetos existentes como botões clicáveis.
- Botão "+ Novo projeto" alterna para modo `creating`.
- Ao selecionar um projeto:
  1. Chama `createSession("Nova conversa", templateName, project.id)`
  2. Navega para `/projects/${project.id}` via `useNavigate`
  3. O `ProjectDetailPage` abre com a aba Chat ativa e a nova sessão disponível na sidebar

**Modo `creating`**:
- Campo de texto para nome do projeto (obrigatório).
- Botão "Criar e continuar":
  1. Chama `createProject(name)`
  2. Chama `createSession("Nova conversa", templateName, project.id)`
  3. Navega para `/projects/${project.id}`
- Botão "Voltar" retorna ao modo `selecting`.

**Estados de loading/erro** inline — spinner no botão durante operações assíncronas.

**Estrutura de estado:**
```typescript
type Mode = "selecting" | "creating";

const [mode, setMode] = useState<Mode>("selecting");
const [projects, setProjects] = useState<Project[]>([]);
const [loading, setLoading] = useState(true);         // carregamento inicial
const [submitting, setSubmitting] = useState(false);  // durante create
const [error, setError] = useState<string | null>(null);
const [newProjectName, setNewProjectName] = useState("");
```

**Imports necessários:**
```typescript
import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { FolderOpen, Plus, ArrowLeft, Loader2 } from "lucide-react";
import { listProjects, createProject } from "../api/projects";
import { createSession } from "../api/chat";
import type { Project } from "../api/types";
```

**Dependências:** Passos 1 e 2 não bloqueiam, mas este passo deve ser concluído antes do Passo 4.

---

### 4. Atualizar `Templates.tsx`

**Arquivo:** `frontend/src/pages/Templates.tsx`

Substituir `handleSelect` e adicionar estado para o modal:

```diff
+ import ProjectSelectorModal from "../components/ProjectSelectorModal";

+ const [selectorTarget, setSelectorTarget] = useState<string | null>(null);

  const handleSelect = async (templateName: string) => {
-   try {
-     const session = await createSession("Nova conversa", templateName);
-     navigate(`/chat?session=${session.id}`);
-   } catch (e) {
-     setError(e instanceof Error ? e.message : "Erro ao criar conversa.");
-   }
+   setSelectorTarget(templateName);
  };
```

Remover o import de `createSession` e `useNavigate` se não forem mais usados em outro lugar.

Adicionar o modal no JSX (junto com os outros modais no final do return):

```tsx
{selectorTarget && (
  <ProjectSelectorModal
    templateName={selectorTarget}
    onCancel={() => setSelectorTarget(null)}
  />
)}
```

**Dependências:** Passo 3 deve estar concluído.

---

### 5. Limpar `Chat.tsx`

**Arquivo:** `frontend/src/pages/Chat.tsx`

Remover a prop `initialSessionId` da interface e do componente — não há mais nenhum consumidor que a passe:

```diff
  interface ChatPageProps {
    projectId?: string;
-   /** Session ID inicial via query-param (modo legado /chat?session=...) */
-   initialSessionId?: string | null;
  }

- export default function ChatPage({ projectId, initialSessionId }: ChatPageProps) {
+ export default function ChatPage({ projectId }: ChatPageProps) {

    const [activeSessionId, setActiveSessionId] = useState<string | null>(
-     initialSessionId ?? null,
+     null,
    );
```

**Dependências:** Passo 4 concluído (garante que nenhum consumidor passa `initialSessionId`).

---

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|---|---|---|
| Usuário sem projetos cadastrados | Alta | Modal exibe mensagem orientativa + opção "Novo projeto" proeminente |
| `createProject` falha (nome vazio, rede) | Baixa | Erro inline no modal, não fecha |
| `createSession` falha após projeto criado | Baixa | Projeto fica criado mas vazio — exibir erro e orientar navegação manual |
| `npm run build` falhar por `initialSessionId` ainda referenciado em algum lugar | Baixa | Rodar `grep -rn initialSessionId` antes de remover a prop |

---

## Critérios de Conclusão

- [ ] `grep -rn "/chat" frontend/src/` retorna zero ocorrências de `navigate` ou `Navigate` apontando para `/chat`
- [ ] `npm run build` passa sem erros de TypeScript
- [ ] Clicar "Usar template" em `TemplatesPage` abre `ProjectSelectorModal`
- [ ] Selecionar projeto existente cria sessão e navega para `/projects/:id` com aba Chat ativa
- [ ] Criar novo projeto cria projeto + sessão e navega para `/projects/:id`
- [ ] Login por e-mail redireciona para `/` (Projects)
- [ ] Não-admin acessando `/admin` é redirecionado para `/` (Projects)
