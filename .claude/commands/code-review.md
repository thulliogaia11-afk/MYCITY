# /code-review — Revisão Sênior de Código

USO: /code-review [arquivo, service, feature ou diff]

Objetivo: fazer revisão sênior específica para MY CITY, Roblox Luau, Rojo, DataStore, Remotes e gameplay político-econômico.

## IMPORTANTE
- Não fazer revisão genérica.
- Não sugerir refactor amplo sem motivo.
- Não alterar arquivos.
- Não ignorar CLAUDE.md.
- Não tratar decisão de produto como bug.

## Escopo
- Arquivos revisados.
- Services afetados.
- Client / server / shared.
- DataStores afetados.
- Remotes afetados.
- Invariants afetados.

## Quando escopo for changed-files
- Rodar `git diff --name-only` e `git diff --stat`.
- Revisar apenas arquivos alterados.
- Não escanear projeto inteiro sem necessidade.
- Se uma dependência crítica estiver faltando, pedir autorização antes de ampliar o escopo.

## Revisão técnica
- Server-authoritative.
- DataStore seguro.
- Sanitizers presentes.
- Remotes protegidos.
- Payload mínimo.
- Respostas { ok, data | error }.
- Logs prefixados [MY CITY].
- Defensive defaults.
- Compatibilidade com cliente antigo.
- Nenhuma mutação direta proibida.
- Nenhum uso inseguro de game.Loaded:Wait() no servidor.
- Nenhuma alteração acidental em DataStore keys.
- Performance em mobile quando UI/cliente for afetado.

## Critical path simulation
- Player novo.
- Player antigo com dados salvos.
- Player sem cidade.
- Player prefeito.
- Player candidato.
- Player votante.
- Desconexão durante chamada.
- Cliente antigo sem novo payload.
- UI aberta enquanto fase política muda.

## Formato obrigatório

### Veredito
APROVADO | APROVADO COM AJUSTES | BLOQUEADO

### Findings
| Severidade | Arquivo | Linha/área | Problema | Correção |
|------------|---------|------------|----------|----------|

### Pontos fortes
Listar o que está bem feito.

### Pontos que não devem mudar
Listar invariants e decisões de produto preservadas.

### Critical path simulation
Resultado de cada caminho testado.

### Mobile/performance
Análise específica se UI/cliente foi afetado.

### Correção mínima
Lista curta, ordenada por prioridade.

### Commit recomendado
Mensagem no padrão: `<arquivo|módulo>: <ação> (<contexto>)`
