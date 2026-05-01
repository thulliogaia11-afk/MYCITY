# /datastore-audit — Auditoria de Persistência

USO: /datastore-audit [service ou DataStore]

Objetivo: auditar persistência com foco em longevidade, segurança contra perda de dados, migração segura e estabilidade do MY CITY.

## IMPORTANTE
- Não modificar arquivos sem autorização explícita.
- Não alterar DataStore keys.
- Não renomear campos persistidos.
- Não mudar serializer/deserializer sem aprovação.
- Não criar `_v2` sem plano explícito.
- Não apagar dados.
- Não inventar arquivos, services ou paths.
- Se algo esperado não existir, declarar NOT FOUND e parar antes de criar arquitetura.

## DataStores principais
- `MY_CITY_PlayerData_v1`
- `MY_CITY_Elections_v1`
- `MY_CITY_Treasury_v1`

Migrações devem ser não-destrutivas. Campo novo com default seguro é permitido. Renomear campo exige plano e possível bump de versão.

## Identidade do DataStore
- Nome exato.
- Service owner lógico.
- Versão atual.
- Escopo dos dados.
- Onde carrega.
- Onde salva.
- Cache em memória.
- Autosave.
- Save em PlayerRemoving / shutdown.

## Sanitização
- Helper dedicado.
- Trata nil, tipo errado, número negativo, NaN/infinito, string vazia, IDs órfãos, listas malformadas, schema antigo.
- Retorna default seguro.
- Nunca lança exceção.
- Padrão de referência: `sanitizeProjectIds` no ElectionService.

## Migração
- SEM MIGRAÇÃO NECESSÁRIA
- MIGRAÇÃO ADITIVA SEGURA
- MIGRAÇÃO COM RISCO
- EXIGE _v2
- BLOQUEADO

Plano 3 fases para remoção:
1. Dual-read / dual-write.
2. Deprecation com fallback.
3. Remoção após janela segura.

## Risco de perda de dados
- Save e Load usam pcall.
- Falha é logada com fallback seguro.
- Sem sobrescrever dado novo com cache antigo.
- Sem concorrência perigosa autosave vs PlayerRemoving.
- Sem mutação direta proibida.
- BeforeSave preserva JobService.StopWork.

## Consistência com gameplay
- Daily missions não são taxadas.
- Passive income não é taxado.
- Apenas runWorkLoop é taxado.
- Impeachment threshold é 70%.
- Auto-voto é bloqueado.
- Nominate aceita projectIds opcional.
- Cliente antigo continua compatível.
- Ledger máximo 50 entradas.

## Formato obrigatório

### Veredito
APROVADO | APROVADO COM RISCOS | BLOQUEADO

### DataStore auditado
| Item | Resultado |
|------|-----------|
| DataStore | |
| Owner | |
| Versão | |
| Lazy-loaded? | |
| Autosave? | |
| Save on shutdown/player removing? | |

### Schema auditado
| Campo | Tipo esperado | Default | Sanitizer | Pode ser nil? | Risco |
|-------|---------------|---------|-----------|---------------|-------|

### Evidência obrigatória
Arquivo, função, comportamento observado, por que importa.

### Riscos de persistência
| Severidade | Risco | Cenário | Impacto | Correção mínima |
|------------|-------|---------|---------|-----------------|

### Migração necessária?
Não | Sim, backward-compatible | Sim, exige _v2 | Bloqueado

### O que NÃO deve ser alterado
DataStore keys e invariants protegidos.

### Próximo passo
Uma única ação recomendada.
