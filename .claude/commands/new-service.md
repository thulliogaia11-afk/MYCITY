# /new-service — Scaffolding de Novo Service

USO: /new-service [NomeDoService]

Crie scaffolding de novo service seguindo os padrões do MY CITY.

## IMPORTANTE
- snake_case para IDs persistidos, camelCase para variáveis Luau, PascalCase para módulos.
- Logs prefixados com [MY CITY].
- Toda função pública documentada.
- Sanitizer dedicado se houver DataStore.
- DataStore key versionada (MY_CITY_[Nome]_v1).
- **Antes de propor novo service, justificar por que nenhum service existente deve receber esta responsabilidade.**
- **Não criar novo service se a responsabilidade pertencer claramente a ElectionService, TreasuryService, JobService ou PlayerDataService.**
- **Se for core político, rodar `/roadmap-gate` e `/political-loop-audit` antes.**
- **Se tocar persistência, rodar `/datastore-audit` antes.**

## Template

local [NomeDoService] = {}

-- Se tiver DataStore:
local store = DataStoreService:GetDataStore("MY_CITY_[Nome]_v1")

local function sanitize[Tipo](raw)
    -- validação tipada com fallback para default seguro
    -- NUNCA lança exceção
end

-- Responsabilidade: [em uma linha]
-- Parâmetros: [lista]
-- Retorna: [tipo] | nil se [condição]
-- Edge cases: [lista]
function [NomeDoService].MinhaFuncao(param)
    -- implementação
end

return [NomeDoService]

## Verificações finais
- [ ] Está em src/server/services/?
- [ ] DataStore key versionada?
- [ ] Sanitizer dedicado para deserialização?
- [ ] Logs prefixados [MY CITY]?
- [ ] Funções públicas documentadas?

## Formato obrigatório

### Service criado
Nome, responsabilidade, escopo.

### Estrutura proposta
Código do scaffolding.

### Integração
Como adicionar no init.server.luau sem quebrar ordem de boot.

### Commits sugeridos
1. Commit X: criar service isolado.
2. Commit Y: integrar com consumidores.

### Próximo passo
Uma única ação recomendada.
