# /think — Pensamento Estruturado

USO: /think [problema a resolver]

Antes de qualquer solução, pense estruturadamente:

1. **Objetivo real** — O que precisamos resolver de verdade? (não o sintoma, a causa)
2. **Contexto** — Quais services, DataStores ou invariants do CLAUDE.md são afetados?
3. **Alternativas** — Liste pelo menos 3 caminhos diferentes com trade-offs honestos
4. **Riscos** — Qual alternativa pode violar invariants sagrados? Qual cria dívida técnica?
5. **Recomendação** — A melhor solução com justificativa clara e critérios de validação

Seja específico para o MY CITY. Não respostas genéricas.

## Formato obrigatório

### Objetivo real

### Contexto afetado
Services, DataStores, invariants e decisões de produto envolvidas.

### Alternativas
| Opção | Descrição | Trade-off |
|-------|-----------|-----------|

### Riscos por alternativa
Qual viola o quê.

### Recomendação
Solução escolhida + justificativa + critérios de validação.

### Próximo comando recomendado
Geralmente: `/roadmap-gate`, `/ui-flow`, ou auditoria específica.
