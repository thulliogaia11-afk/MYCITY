# /remote-audit — Auditoria de Remotes

USO: /remote-audit [nome do Remote ou feature]

Objetivo: auditar RemoteFunction, RemoteEvent ou conjunto de Remotes com foco em segurança Roblox, consistência server-authoritative e proteção do gameplay político-econômico do MY CITY.

## IMPORTANTE
- Este comando é AUDITORIA.
- Não modificar arquivos sem autorização explícita.
- Não refatorar por gosto.
- Não alterar DataStore keys.
- Não inventar arquivos, services, remotes ou paths.
- Se algo esperado não existir, declarar NOT FOUND e parar.
- O cliente nunca decide Money, XP, Reputation, Votes, Treasury, Project activation, Job rewards, Inventory ou City state.

## Contexto obrigatório
- ElectionService é core político.
- JobService é core econômico.
- TreasuryService guarda tesouro per-cidade.
- ProjectCatalog contém 10 projetos civis.
- Servidor já aceita projectIds opcionais em Nominate.
- Cliente antigo sem projectIds deve continuar funcionando.
- Auto-voto é bloqueado.
- Impeachment threshold é 70%.

## Escopo auditado
- Remotes envolvidos.
- Arquivos client que chamam o Remote.
- Arquivos server que recebem o Remote.
- Services afetados.
- Se toca dinheiro, reputação, voto, tesouro, projeto, loja, job, cidade ou impeachment.

## Contrato de payload
- `typeof(payload) == "table"`.
- `action` é string quando aplicável.
- IDs são strings, quantidades são números positivos, finitos, dentro de range.
- Payload não envia userId/player/cityName forjável.
- Servidor usa o `player` real do handler, ignora identidade enviada pelo cliente.

**Regra:** payload carrega intenção mínima; servidor reconstrói autoridade.

## Validações server-side obrigatórias
- [ ] Payload é tabela.
- [ ] Action é permitida.
- [ ] IDs validados contra config real (ProjectCatalog, JobService).
- [ ] City validada via CityService.
- [ ] Player city confere com a ação.
- [ ] Fase política confere.
- [ ] Permissão validada.
- [ ] Reputação mínima validada.
- [ ] Funds validados.
- [ ] Cooldown validado.
- [ ] Rate limit por player e por action.
- [ ] Payload gigante e tabelas malformadas rejeitados.
- [ ] Duplicação por spam neutralizada.
- [ ] Ação idempotente quando necessário.

## Exploit simulation — pelo menos 8 payloads maliciosos
1. Money falso.
2. Reputation falsa.
3. cityName / userId forjado.
4. Voto múltiplas vezes.
5. Auto-voto.
6. projectIds inválidos, duplicados ou com mais/menos de 3 itens.
7. Ação fora da fase política correta.
8. Spam de impeachment ou voto.
9. Reward forçado de job/mission.
10. Treasury forçado.
11. Compra sem funds.
12. Payload gigante / tabela profunda malformada.

## Resposta do Remote
- `{ ok = true, data = ... }` ou `{ ok = false, error = "ERROR_CODE" }`.
- Nunca retorna profile completo, DataStore raw ou estrutura interna.
- Error codes pertencem ao Catálogo Central de ERROR_CODEs do CLAUDE.md.

## Severidade
- **CRÍTICO:** exploit de dinheiro, voto, reputação, tesouro, DataStore ou permissão política.
- **ALTO:** quebra do loop político, duplicação de reward, impeachment inconsistente.
- **MÉDIO:** erro de UI, cooldown ausente em ação pouco crítica.
- **BAIXO:** naming, logs, organização.

## Formato obrigatório

### Veredito
APROVADO | APROVADO COM RISCOS | BLOQUEADO

### Remote map
| Item | Resultado |
|------|-----------|
| Feature auditada | |
| Remote(s) | |
| Client caller(s) | |
| Server handler(s) | |
| Services afetados | |
| Toca dinheiro/reputação/voto/tesouro? | |

### Evidência obrigatória
Arquivo, função, comportamento observado, por que importa.

### Riscos encontrados
| Severidade | Arquivo | Problema | Impacto | Correção mínima |
|------------|---------|----------|---------|-----------------|

### Exploit simulation
| Payload malicioso | Bloqueado hoje? | Onde bloqueia | Falha restante |
|-------------------|-----------------|---------------|----------------|

### O que NÃO deve ser alterado
Invariants relevantes do CLAUDE.md.

### Próximo passo
Uma única ação recomendada, com escopo pequeno.
