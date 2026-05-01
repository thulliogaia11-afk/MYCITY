# /new-mission — Scaffolding de Nova Missão

USO: /new-mission [job] [distrito/local]

Crie scaffolding completo de nova missão para o job indicado.

## IMPORTANTE
- Verificar se o job existe no JobService.
- Daily missions NÃO são taxadas — decisão de produto, não alterar.
- Seguir padrões do MissionService existente.
- Verificar identidade da cidade:
  - Ironholm = industrial / formal
  - Solara = cultural / natural

## Estrutura da missão

1. **Config:** título, descrição, recompensa (CC + reputação), local, duração, cooldown.
2. **Decisão de tributação:** é runWorkLoop (taxado) ou missão bônus (não taxado)? Justificar.
3. **AcceptMission:** ProximityPrompt + RemoteEvent + validação server-side.
4. **Lógica de trabalho:** duração, feedback visual, possibilidade de falha, estados intermediários.
5. **CompleteMission:** ProximityPrompt + validação server-side + recompensa + update de stats.
6. **Integração:** onde no MissionService é registrada, como spawna ProximityPrompts.

## Estados especiais
- E se o jogador desconectar durante a missão?
- E se o ProximityPrompt for spammado?
- E se outro jogador tentar interferir?

## Formato obrigatório

### Missão proposta
Nome, job, local, recompensa.

### Decisão de tributação
Taxado ou não, com justificativa.

### Fluxo
Aceitar → Trabalhar → Completar → Recompensa.

### Validações server-side
Lista de checks.

### Implementação mínima
- Arquivos afetados:
- Services afetados:
- Remotes envolvidos:

### Próximo passo
Uma única ação recomendada.
