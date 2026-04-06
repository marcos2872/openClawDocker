# Plano: Melhorias na Skill de Criação de PD&I — Feedback Jacto/Drones

**Data:** 2026-04-06
**Autor:** agente-plan
**Status:** aprovado

---

## Objetivo

Incorporar o feedback recebido na revisão de uma apresentação de PD&I gerada pelo agente
ao arquivo `src/skills/pptx_creation.md`, tornando as instruções suficientemente específicas
para evitar que os mesmos problemas se repitam em gerações futuras.

São quatro grupos de mudança: Escopo/EAP, Premissas, Matriz de Riscos e Pesquisa de
Anterioridade — além da atualização do checklist de avaliação (seção 7).

---

## Escopo

**Dentro do escopo:**
- Edição de `src/skills/pptx_creation.md`
- Adição de regras/diretrizes nas seções 4.4, 4.5, 4.13 e 4.14
- Atualização do checklist (seção 7) com os novos itens de verificação

**Fora do escopo:**
- Alterações em código Python ou TypeScript
- Mudanças em outros arquivos de skill (`rag_research.md`, `web_research.md`)
- Criação de novos templates PPTX
- Alteração de testes existentes

---

## Arquivos Afetados

| Arquivo | Ação | Motivo |
|---|---|---|
| `src/skills/pptx_creation.md` | modificar | Incorporar as 4 categorias de feedback |

---

## Sequência de Execução

### 1. Seção 4.4 — Pesquisa de Anterioridade

**Arquivo:** `src/skills/pptx_creation.md`

**O que fazer:** Logo após o bloco de `**Regras:**` da seção 4.4, acrescentar
o parágrafo abaixo (antes da linha `---` que encerra a seção):

```markdown
**Campos booleanos — preenchimento obrigatório:**
- O campo **"Validação de Premissas"** deve ser respondido como **"NÃO"** para projetos
  ainda em fase de proposta ou desenvolvimento. A validação só ocorre após execução e
  análise de resultados. Não confundir com *análise* de premissas (planejamento), que
  pode ser respondida como "SIM".
```

**Dependências:** nenhuma — edição isolada.

---

### 2. Seção 4.5 — Escopo

**Arquivo:** `src/skills/pptx_creation.md`

**O que fazer:** No bloco de `**Regras:**` da seção 4.5, adicionar dois novos itens ao final:

```markdown
- Referenciar explicitamente a EAP e as macro-entregas dentro do texto de Escopo, com
  link ou menção à seção correspondente, para que o leitor consiga navegar entre as partes
  do documento sem perder o fio condutor.
- Quando o projeto envolver hardware ou plataformas de terceiros (ex.: drones, robôs,
  PLCs, sensores), incluir um item de escopo declarando a agnosticidade do sistema:
  *"O sistema desenvolvido será agnóstico quanto ao modelo e fabricante de [hardware],
  sendo aplicável a diferentes plataformas e fabricantes compatíveis."*
```

**Dependências:** nenhuma — edição isolada.

---

### 3. Seção 4.13 — Premissas

**Arquivo:** `src/skills/pptx_creation.md`

**O que fazer:** Após o bloco de premissas obrigatórias para projetos de software,
adicionar um novo bloco condicional para **projetos com testes em campo ou hardware externo**:

```markdown
**Para projetos com testes em campo ou uso de hardware externo**, incluir obrigatoriamente:

> - Os testes de avaliação serão conduzidos em até **[N] cenários operacionais distintos**,
>   previamente definidos com a empresa contratante. (Substituir [N] pelo número acordado;
>   evitar premissas abertas como "diferentes cenários" sem quantificação.)
> - O projeto será desenvolvido em caráter experimental; todos os aspectos de segurança
>   operacional, bem como seus impactos e consequências, são de inteira responsabilidade
>   da empresa contratante.
> - Eventuais hardwares operacionais necessários ao longo do projeto (ex.: tablets,
>   controladores, dispositivos de campo) serão fornecidos pela empresa contratante,
>   caso haja necessidade identificada durante a execução.
```

**Dependências:** nenhuma — edição isolada.

---

### 4. Seção 4.14 — Matriz de Riscos

**Arquivo:** `src/skills/pptx_creation.md`

**O que fazer:** Após a lista de riscos existente para projetos de software, adicionar
subseção com riscos obrigatórios para **projetos com componente físico/operacional**,
além de duas regras de linguagem:

```markdown
**Para projetos com hardware, operação em campo ou testes físicos**, incluir obrigatoriamente
os seguintes riscos na matriz:

| Risco | Causa | Consequências | Exposição | Estratégia | Ação de Contenção | Responsável |
|---|---|---|---|---|---|---|
| Falha sistêmica com colisão ou perda de equipamento | Erro de software/hardware durante operação autônoma | Danos materiais, acidentes, interrupção do projeto | Alto | Mitigar | Definir protocolos de segurança operacional; delimitar responsabilidade contratual da empresa | EMPRESA |
| Atraso na chegada ou comodato de equipamento importado | Burocracia alfandegária, logística internacional | Atraso no cronograma, bloqueio de atividades dependentes | Médio | Mitigar | Iniciar processo de importação com antecedência; mapear fornecedores alternativos; incluir buffer de prazo | EMPRESA |
| Condições climáticas e geográficas adversas nos cenários de teste | Particularidades do ambiente escolhido (chuva, vento, altitude, temperatura) | Comprometimento da reprodutibilidade dos resultados e dos testes | Médio | Mitigar | Planejar janelas de teste com margem climática; documentar condições de cada sessão | SENAI / EMPRESA |
| Riscos de segurança operacional (colisões, quedas, impactos) | Falha no sistema de controle ou comunicação durante voo/operação | Acidentes com equipamentos, pessoas ou propriedades | Alto | Mitigar | Estabelecer perímetro de segurança; treinar operadores; definir procedimentos de emergência | EMPRESA |

**Regras adicionais de linguagem para ações de contenção:**
- ❌ **NÃO usar** "assinatura de TSM" como ação de contenção — esse termo é interno
  e não deve constar no documento entregue à empresa.
- ✅ **Usar em substituição:** "potencial aditivo de prazo e/ou custo, a ser formalizado
  mediante acordo entre as partes."

**Regra sobre gates de Go/No-Go:**
- Avaliar, junto à equipe de projeto, a inclusão de **gates decisórios de Go/No-Go**
  ao término de cada macroentrega. Quando aplicável, registrar como premissa:
  *"Ao término de cada macroentrega, será realizada uma avaliação de Go/No-Go para
  decidir sobre a continuidade, pivotagem ou encerramento do projeto."*
  e como risco: risco de encerramento antecipado caso uma entrega não atinja os
  critérios mínimos acordados.
```

**Dependências:** nenhuma — edição isolada, mas deve ser feita após o passo 3
para manter a coerência de leitura (premissas → riscos).

---

### 5. Seção 7 — Checklist de Avaliação

**Arquivo:** `src/skills/pptx_creation.md`

**O que fazer:** Adicionar 6 novos itens ao checklist existente, agrupados
sob um subtítulo de "Projetos com campo ou hardware externo":

```markdown
**Projetos com campo ou hardware externo:**
- [ ] Escopo menciona a agnosticidade do sistema (quando aplicável)
- [ ] EAP e macro-entregas referenciadas dentro da seção de Escopo
- [ ] Cenários de teste quantificados nas premissas (sem escopo aberto)
- [ ] Premissa de responsabilidade de segurança atribuída à empresa contratante
- [ ] Premissa de fornecimento de hardware pela contratante incluída
- [ ] Riscos operacionais físicos na matriz (colisão, clima, importação, segurança)
- [ ] Ações de contenção sem o termo "TSM"; substituído por "aditivo de prazo e/ou custo"
- [ ] Gates de Go/No-Go avaliados e registrados (premissa ou risco)
- [ ] Campo "Validação de Premissas" (Pesquisa de Anterioridade) respondido como "NÃO"
```

**Dependências:** deve ser feito por último, após todas as seções anteriores estarem
consolidadas (passo 4 conclui a lógica de conteúdo; passo 5 apenas espelha no checklist).

---

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|---|---|---|
| Regras adicionais tornarem a skill muito longa e difícil de ler | Baixa | Usar subseções condicionais ("Para projetos com hardware…") — não afeta projetos de software puro |
| Conflito com premissas já existentes para software (seção 4.13) | Baixa | O novo bloco é aditivo e explicitamente marcado como condicional |
| Checklist crescer demais e virar letra morta | Média | Agrupar os novos itens sob subtítulo específico para projetos de campo |

---

## Critérios de Conclusão

- [ ] Seção 4.4 contém regra explícita sobre "Validação de Premissas = NÃO" em fase de proposta
- [ ] Seção 4.5 instrui referenciar a EAP no Escopo e mencionar agnosticidade quando aplicável
- [ ] Seção 4.13 contém bloco condicional com 3 premissas para projetos com campo/hardware
- [ ] Seção 4.14 contém tabela de riscos operacionais físicos e regras sobre TSM e Go/No-Go
- [ ] Seção 7 (checklist) reflete todos os novos itens
- [ ] Nenhuma outra seção do arquivo foi alterada ou removida
- [ ] O arquivo permanece em português brasileiro e formatação Markdown válida
