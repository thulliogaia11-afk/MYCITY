# MY CITY - CLAUDE.md
# Parceiro Técnico: Claude (Anthropic) | Autor: Thulio
# Versão: 2.1.1 - Blindagem de Produção + Execução Cirúrgica (cosmetic polish)
# Última atualização: Após Commit 7 + Spec de Identidade Regional v1 + Hardening v1 + Ajustes v2.1 + Polimento v2.1.1
# Este arquivo é lido automaticamente pelo Claude Code em cada sessão.
# Regras marcadas como [INVARIANT] são obrigatórias. [PRODUCT] deve ser preservada salvo autorização explícita. [ROADMAP] orienta prioridade, mas pode evoluir com justificativa técnica.

---

## NOTA v2.1 - AJUSTES ADITIVOS

Esta versão mantém a base da v2.0 intacta. Os ajustes v2.1 não mudam a arquitetura do jogo, não alteram o roadmap central e não rebaixam nenhuma regra server-authoritative. Eles apenas tornam o arquivo mais seguro para uso real no Claude Code, removendo ambiguidades operacionais que poderiam gerar commits inflados, execução inventada ou conflito entre o documento e o comando atual do autor.

Melhorias adicionadas:
- interpretação mais precisa dos níveis de autoridade;
- protocolo operacional para qualquer tarefa de código;
- regra anti-refactor fora de escopo;
- fallback quando slash commands não existirem;
- resolução explícita entre push schedule e comandos com "commit and push";
- separação entre Commit 8 e auditoria geral de rate limiting;
- regra para não inventar estado do projeto sem `git status` e `git log`.

## NOTA v2.1.1 - POLIMENTO COSMÉTICO

Apenas ajustes cosméticos sobre v2.1, sem mudança de regra ou conteúdo:
- removida duplicação de tag em títulos (ex: "LEI ZERO [INVARIANT] INVARIANT" → "LEI ZERO [INVARIANT]");
- padronizada a lista da Lei Zero para português, mantendo termo técnico em inglês entre parênteses quando relevante.

## SISTEMA DE GOVERNANÇA - 3 NÍVEIS DE AUTORIDADE [GOV]

Toda regra deste documento pertence a um destes três níveis. **Confundir os níveis é o erro mais perigoso possível.**

| Nível | Significado | Como tratar |
|-------|-------------|-------------|
| **[INVARIANT]** | Lei técnica que protege integridade do sistema | NUNCA violar sem autorização explícita do autor. Violação = bug grave. |
| **[PRODUCT]** | Escolha consciente do autor sobre design do jogo | NÃO "corrigir" como se fosse bug. Pode ser revisitada, mas só por decisão explícita. |
| **[ROADMAP]** | Planejamento futuro, sujeito a evolução | Pode mudar com justificativa. Não é lei imutável. |

Cada seção tem sua etiqueta. Antes de propor qualquer mudança, identifique o nível.

### Regra de interpretação v2.1

Nem todo texto narrativo deste arquivo é uma trava técnica. O agente deve distinguir:
- lei técnica marcada como INVARIANT;
- decisão de produto marcada como PRODUCT DECISION;
- planejamento marcado como ROADMAP;
- contexto descritivo usado para entender o projeto.

Se houver conflito entre contexto narrativo e uma regra marcada como INVARIANT, o INVARIANT vence. Se houver conflito entre ROADMAP e comando explícito do autor na sessão atual, o agente deve explicar o conflito e seguir o autor, salvo se isso violar um INVARIANT.

---

## LEI ZERO - SERVER-AUTHORITATIVE [INVARIANT]

**Este projeto é Roblox. Roblox é exploitado trivialmente por clientes maliciosos (Synapse, Krnl, etc.).**

**O cliente NUNCA decide. O cliente apenas envia intenção. O servidor valida tudo e decide.**

O cliente NUNCA tem autoridade sobre:
- Dinheiro (Money)
- XP
- Reputação (Reputation)
- Inventário (Inventory)
- Salário (Salary)
- Votos (Votes)
- Impeachment
- Tesouro da cidade (Treasury)
- Projetos políticos pledged ou em execução
- Recompensas (missões, daily, peer review)
- Propriedade de casa / passive income
- Início, conclusão ou demissão de jobs

**Validação client-side existe apenas como UX (feedback instantâneo, hide/show de botões).**
**Não é segurança. Nunca foi. Nunca será.**

Toda lógica de jogo crítica acontece no servidor. Cliente recebe resultado, não calcula.

---

## REGRA DE FOCO - FECHAR O LOOP POLÍTICO ANTES DE TUDO [PRODUCT]

**O coração do MY CITY é o ciclo: promessa -> eleição -> execução -> consequência -> avaliação.**

Antes de qualquer feature nova, este loop precisa fechar. Sprint 1 é intocável:

```
Commit 8  -> ElectionUI com seleção de 3 projetos
Commit 9  -> ApprovalService (executa effect structs)
Commit 10 -> Painel de transparência cidadão
```

**Enquanto este loop não fecha, qualquer outra feature é distração.**

Não importa quão tentadora seja a ideia (Solara viva, sazonalidade, novos jobs, novos clubes).
Sem o loop político fechado, MY CITY não é MY CITY - é só "mais um RP".

Se o autor pedir feature fora deste escopo durante Sprint 1, lembrá-lo desta regra.
Esta regra protege o autor de si mesmo (e o Claude Code de empolgação).

---

## 1. VISÃO DO PROJETO [PRODUCT]

MY CITY é um jogo social de simulação urbana no Roblox.
Seu diferencial absoluto não é o mapa bonito nem os jobs - é a **política real com consequência**.

Cidades têm prefeitos eleitos. Prefeitos executam projetos que mudam a economia real da cidade.
Eleitores veem o resultado. Prefeitos ruins são destituídos por impeachment.
Jogadores sentem que ser alguém importa.

**As 3 camadas de desejo que tudo deve servir:**
1. Desejo visual - "eu quero viver aqui"
2. Desejo de progressão - "eu quero subir aqui"
3. Desejo de domínio social - "eu quero ser alguém importante aqui"

**Princípio central:** Nenhuma cidade pode ser autossuficiente. A interdependência é o motor narrativo.

---

## 2. ARQUITETURA DO PROJETO [INVARIANT]

### Stack
- Engine: Roblox Studio (Luau)
- Estrutura: Rojo (disco -> Studio runtime)
- Toolchain: Rokit
- Versionamento: Git + GitHub
- IDE: Cursor + Claude Code

### Mapeamento Rojo (default.project.json)
```
ReplicatedStorage.Shared  ←->  src/shared/
ServerScriptService.Server ←->  src/server/
StarterPlayer.StarterPlayerScripts.Client ←->  src/client/
```

### Árvore de pastas
```
src/
├── client/
│   ├── ElectionUI.client.luau
│   ├── MainUI.client.luau
│   ├── PlayerReviewUI.client.luau
│   ├── ShopUI.client.luau
│   └── [outros módulos de UI]
├── server/
│   ├── init.server.luau           ← boot principal - TOCAR COM CUIDADO EXTREMO
│   └── services/
│       ├── PlayerDataService.luau  ← SAGRADO - ver seção 6
│       ├── CityService.luau
│       ├── ReputationService.luau
│       ├── ElectionService.luau    ← core político
│       ├── JobService.luau         ← core econômico
│       ├── TreasuryService.luau    ← criado commit 3
│       ├── HouseService.luau
│       ├── HouseEntryService.luau
│       ├── RankingService.luau
│       ├── OutfitService.luau
│       ├── ClubService.luau
│       ├── ClubFacadeService.luau
│       ├── ClubDoorService.luau
│       ├── DrinkService.luau
│       ├── SocialRatingService.luau
│       ├── ReviewService.luau
│       ├── ShopService.luau
│       └── MissionService.luau
└── shared/
    └── ProjectCatalog.luau         ← criado commit 5
```

---

## 3. PADRÃO OBRIGATÓRIO DE REMOTES [INVARIANT]

**Todo RemoteEvent e RemoteFunction segue este protocolo. Sem exceção.**

### Estrutura padrão de chamada server-side

```luau
-- Todo handler de Remote DEVE seguir esta estrutura
local function handleMyRemote(player, payload)
    -- 1. VALIDAR TIPO DO PAYLOAD
    if typeof(payload) ~= "table" then
        return { ok = false, error = "INVALID_PAYLOAD" }
    end

    -- 2. VALIDAR ACTION (se aplicável)
    if payload.action ~= "expected_action" then
        return { ok = false, error = "INVALID_ACTION" }
    end

    -- 3. VALIDAR IDS CONTRA CONFIGS REAIS
    -- (ex: ProjectCatalog.IsValidProjectId, JobService.GetJobs)
    if not SomeConfig.IsValid(payload.id) then
        return { ok = false, error = "INVALID_ID" }
    end

    -- 4. VALIDAR CIDADE / FASE / PERMISSÕES / COOLDOWNS
    local city = CityService.GetPlayerCity(player)
    if not city then
        return { ok = false, error = "NOT_IN_CITY" }
    end

    if ElectionService.GetPhase(city) ~= "candidacy" then
        return { ok = false, error = "INVALID_PHASE" }
    end

    -- 5. CHAMAR SERVICE SERVER-SIDE
    local result = SomeService.DoThing(player, payload)

    -- 6. RETORNAR RESPOSTA ESTRUTURADA
    if result.success then
        return { ok = true, data = result.publicData }
    else
        return { ok = false, error = result.errorCode }
    end
end
```

### Formato de resposta - sempre uma destas duas estruturas:

```luau
-- Sucesso
{ ok = true, data = <apenas dados públicos relevantes> }

-- Erro
{ ok = false, error = "ERROR_CODE_EM_SCREAMING_SNAKE_CASE" }
```

### Catálogo de ERROR_CODEs padronizados

| Código | Significado |
|--------|-------------|
| `INVALID_PAYLOAD` | Payload não é tabela ou estrutura errada |
| `INVALID_ACTION` | Action não reconhecida |
| `INVALID_ID` | ID não existe no catálogo (project, job, etc.) |
| `NOT_IN_CITY` | Jogador não está atribuído a uma cidade |
| `INVALID_PHASE` | Fase eleitoral não permite esta ação |
| `INSUFFICIENT_REPUTATION` | Reputação abaixo do mínimo exigido |
| `INSUFFICIENT_FUNDS` | Money insuficiente |
| `COOLDOWN_ACTIVE` | Ação em cooldown |
| `ALREADY_VOTED` | Jogador já votou nesta eleição |
| `ALREADY_NOMINATED` | Jogador já é candidato |
| `SELF_VOTE_BLOCKED` | Tentativa de auto-voto |
| `RATE_LIMITED` | Demasiadas chamadas em curto período |
| `INTERNAL_ERROR` | Falha inesperada do servidor |

### Regra de Ouro de Resposta

**NUNCA retornar profile completo, DataStore raw, ou estrutura interna do servidor para o cliente.**
**Retornar apenas os campos que o cliente precisa para renderizar.**

[WRONG] Errado:
```luau
return { ok = true, data = playerProfile }  -- vaza tudo
```

[OK] Certo:
```luau
return { ok = true, data = { money = 250, reputation = 48 } }  -- só o necessário
```

### Rate limiting

Todo Remote crítico (votos, nominate, impeachment, propose trade) DEVE ter rate limit por jogador.
Padrão: máximo 1 chamada a cada 2 segundos. Excesso retorna `RATE_LIMITED`.

### Escopo de hardening de Remotes v2.1

Não transformar qualquer feature commit em auditoria geral de Remotes. Se uma tarefa modificar um Remote específico, auditar e proteger esse Remote dentro do escopo. Auditoria global de todos os Remotes deve ser commit próprio de hardening, com mensagem e validação próprias.

Exemplo: Commit 8 deve focar em ElectionUI e seleção de projetos. Só mexer em Remote server-side se a integração exigir. Não abrir revisão global de rate limiting dentro do Commit 8.

---

## 4. DATASTORES - LEI DE OURO [INVARIANT]

O projeto usa **3 DataStores com escopos não-sobrepostos**. Nunca misturar.

| DataStore | Owner | Campos principais |
|-----------|-------|-------------------|
| MY_CITY_PlayerData_v1 | PlayerDataService | Money, XP, Reputation, Job, City, Reviews, AverageRating, MissionProgress, DismissedFrom, DismissalTime |
| MY_CITY_Elections_v1 | ElectionService | phase, mandateEndTime, currentMayor, candidates (com projectIds), voters, impeachment, activeTrades |
| MY_CITY_Treasury_v1 | TreasuryService | balance, ledger (50 entradas: kind, amount, label, timestamp) |

### Checklist Obrigatório de Migração de Schema

**Adicionar campo novo (com default seguro):**
- [OK] Permitido. Sanitizer trata ausência retornando default.
- Exemplo correto: campo `projectIds` adicionado ao CandidateData no commit 6.

**Renomear campo existente:**
- [WARN] EXIGE bump de versão (`_v1` -> `_v2`).
- Justificativa: clientes/servidores antigos podem ainda gravar com o nome antigo.

**Remover campo existente:**
- [ZERO] EXIGE plano de migração concreto:
  1. **Fase 1 (dual-write):** parar de ler o campo, mas continuar gravando default. Mínimo 14 dias.
  2. **Fase 2 (deprecation):** parar de gravar. Sanitizer ignora se vier do DataStore.
  3. **Fase 3 (remoção):** remover do schema só após confirmação de que nenhum dado em produção depende.

**Mudar key de DataStore:**
- [ZERO] EXIGE plano de migração explícito documentado em ADR.
- Esta operação é irreversível na prática - testar duas vezes, executar uma.

### Regras invioláveis de sanitização

- Toda deserialização de DataStore DEVE passar por sanitizer dedicado.
- Sanitizer NUNCA lança exceção - sempre retorna valor válido ou default.
- Sanitizer trata: `nil`, tipo errado, valores fora de range, IDs órfãos, listas malformadas.
- Padrão de referência: `sanitizeProjectIds` no ElectionService.

---

## 5. INVENTÁRIO DE SERVICES - ESTADO ATUAL [INVARIANT] (estado) + [ROADMAP] (pendentes)

### ESTÁVEIS (não modificar sem necessidade explícita)
- **PlayerDataService** - perfil, persistência, autosave, BeforeSave hook
- **CityService** - registro e validação de Ironholm / Solara
- **ReputationService** - GetReputation, AddReputation, SetReputation
- **HouseService / HouseEntryService** - 4 distritos, passive income, ProximityPrompts
- **RankingService** - pontuação agregada por cidade, log periódico
- **ClubService / ClubFacadeService / ClubDoorService / DrinkService** - 4 tiers de clube
- **SocialRatingService / ReviewService** - peer review 1-5 estrelas, gating por distância
- **OutfitService** - acessórios visuais por job, reaplica em CharacterAdded
- **ShopService** - 7 lojas, vitrine automática, aplicação de cosméticos
- **MissionService** - spawning dinâmico por job, ProximityPrompt, não taxado

### CORE POLÍTICO (modificar com testes obrigatórios em Studio)
- **ElectionService** - ciclos de 24h, fases mandate/candidacy/voting/counting, impeachment 70%, trade deals, ValidateCampaignProjects, projectIds no schema
- **JobService** - 10 jobs, daily missions, streak, 5% imposto via payPlayerWithTax -> TreasuryService.Deposit
- **TreasuryService** - tesouro per-cidade, ledger 50 entradas rotativas, carregamento lazy, defesa contra rate limit

### MÓDULOS SHARED
- **ProjectCatalog** - 10 projetos civis tipados (id, displayName, costCC, durationSeconds, effect struct), sem consumidores ativos ainda

### PENDENTES - A CRIAR (roadmap)
- **ApprovalService** - executará effect structs dos projetos pledgados durante mandato
- **LegacyService** - sistema de legado do prefeito (tier de mandato, histórico acumulado)
- **CityIdentityService** - multiplicadores econômicos por cidade, interdependência forçada

---

## 6. INVARIANTS SAGRADOS - NUNCA VIOLAR [INVARIANT]

### PlayerDataService
- É o sistema de persistência central. Todo acesso a dados do jogador passa por ele.
- NUNCA escrever diretamente no profile do jogador sem usar GetData/SetData.
- O hook BeforeSave executa JobService.StopWork - não remover este hook.
- DataStore key: MY_CITY_PlayerData_v1 - não alterar sem migração planejada.

### ElectionService
- Backward compatibility: Nominate aceita projectIds como parâmetro OPCIONAL.
- Cliente do commit 2 (sem projectIds) deve continuar funcionando.
- NUNCA remover o parâmetro opcional sem atualizar o cliente simultaneamente.
- Threshold de impeachment é 70% (0.7) - decisão de produto, não alterar sem aprovação do autor.
- Auto-voto é bloqueado - não remover este guard.

### TreasuryService
- Se Deposit falha por rate limit, jogador ainda recebe o salário líquido.
- Taxa é descartada em vez de criar inconsistência. Este comportamento é intencional.
- Ledger máximo de 50 entradas - rotação oldest-first é obrigatória.

### JobService
- Daily missions e passive income NÃO são taxados. Apenas runWorkLoop.
- Esta é decisão de produto documentada - não "corrigir" como se fosse bug.
- Cooldown de 6 dias após dismissal - não reduzir sem autorização.

### init.server.luau
- RemoteEvents/RemoteFunctions DEVEM ser criados sincronicamente no topo, ANTES de qualquer require de service.
- NUNCA usar game.Loaded:Wait() no servidor.
- Qualquer alteração neste arquivo exige boot test completo no Studio.

---

## 7. PROTOCOLO DE TESTE NO ROBLOX STUDIO [INVARIANT]

**Após mexer em service, Remote ou DataStore - sempre executar este protocolo antes de commitar.**

### Checklist obrigatório

1. [ ] **Sincronização Rojo** - abrir o projeto no Roblox Studio com Rojo conectado
2. [ ] **Play Solo** - pressionar Play, aguardar boot completo
3. [ ] **Output limpo** - verificar console: nenhum erro vermelho, nenhum warning não esperado
4. [ ] **Boot test** - confirmar logs `[MY CITY]` de cada service iniciando na ordem correta
5. [ ] **Fluxo afetado** - testar manualmente o caminho que foi modificado
6. [ ] **Multi-player (se Remote)** - Test -> Start Server + Start 1 Player; testar interação cliente↔servidor
7. [ ] **DataStore não renomeado** - verificar que keys (MY_CITY_PlayerData_v1, MY_CITY_Elections_v1, MY_CITY_Treasury_v1) estão intactas
8. [ ] **Invariants preservados** - revisar a seção 6 mentalmente

### Quando exigir Start Server + Player

Sempre que a mudança envolver:
- RemoteEvent ou RemoteFunction novo ou modificado
- Comunicação cliente ↔ servidor de qualquer tipo
- ProximityPrompt cuja interação dispara código no servidor
- Qualquer fluxo de dois jogadores (peer review, trade, vote)

Play Solo NÃO captura bugs de network. Não vale como teste de Remote.

### Falhas que devem bloquear commit

- Erro vermelho no Output, mesmo que "pareça inofensivo"
- Loop infinito ou yield travado
- Service que não inicia
- Profile que não carrega
- DataStore que retorna `nil` quando deveria ter dado default

---

## 8. IDENTIDADE DAS CIDADES (Spec v1 - Abril 2026) [PRODUCT]

### Ironholm - Cidade Metropolitana
- **Inspiração:** Londres, Nova York, Tóquio
- **Tema:** Capital industrial e financeira. Arquitetura urbana densa, fábricas, instituições financeiras.
- **Ponto forte:** Produção industrial, serviços financeiros, salários altos em jobs tier 2 e 3.
- **Ponto fraco:** Dependência de importação de alimentos, recursos naturais, turismo cultural.
- **Perfil de jogador:** Ambição por carreira formal, acumulação de riqueza, status corporativo.
- **Jobs exclusivos/favorecidos:** Factory Worker, Police Officer, Firefighter, Doctor, Electrician, Security.

### Solara - Cidade do Interior
- **Inspiração:** Toscana, Provence, vilas mediterrâneas agroturísticas.
- **Tema:** Agricultura, turismo natural, artesanato, energia limpa. Ritmo pausado, comunidade forte.
- **Ponto forte:** Produção de alimentos, turismo, artesanato, passive income em propriedades rurais.
- **Ponto fraco:** Limitação industrial, baixa oferta de jobs tier 3, dependência de bens manufaturados.
- **Perfil de jogador:** Influência social, rede de contatos, prestígio cultural, vida comunitária.
- **Jobs exclusivos/favorecidos:** Tour Guide, Nurse, Teacher + Farmer/Artisan (futuros).

### Lei de Interdependência
- Ironholm precisa de Solara: alimentos baratos, turismo cultural, recursos naturais.
- Solara precisa de Ironholm: bens manufaturados, serviços financeiros, jobs tier 3.
- Esta tensão é o motor dos Trade Deals. Quando prefeitos negociam mal, AMBAS as cidades sofrem.
- Princípio: **Nenhuma cidade pode ser autossuficiente. Sempre.**

### Cidades 3 e 4 [ROADMAP]
- Arquitetura de CityService DEVE suportar adição sem refactor.
- Identidades a serem desenhadas em sprints futuros.
- Mesmo princípio: identidade distinta + dependência forçada de outras cidades.

---

## 9. SISTEMA DE LEGADO DO PREFEITO [PRODUCT]

Mandatos são avaliados automaticamente em 3 dimensões:

| Dimensão | Métrica | Peso (a balancear) |
|----------|---------|-------------------|
| Execução de projetos | Quantos dos 3 pledgados foram ativados | Alto |
| Aprovação popular | % de cidadãos com rating positivo do mandato | Médio |
| Saúde econômica | Variação de tesouro, ranking e população | Médio |

**4 tiers de classificação de mandato** - valores exatos sujeitos a balanceamento iterativo após observação do meta.

O bloqueio pós-impeachment é **segmentado por cidade**:
- Jogador pode continuar em outras cidades
- Paga o preço da queda APENAS na cidade que falhou em governar
- Substitui a regra anterior de ban de 7 dias único

---

## 10. FLUXO POLÍTICO COMPLETO (visão final) [ROADMAP]

```
CANDIDACY PHASE
  Jogador seleciona 3 projetos do ProjectCatalog
  Escreve campaignMessage
  Envia Nominate(player, message, [projectId1, projectId2, projectId3])
  -> Servidor valida tudo, ignora qualquer dado calculado pelo cliente
         v
VOTING PHASE
  Eleitores veem candidatos + projetos pledgados
  Votam (sem auto-voto, sem voto órfão de outra cidade)
  -> Servidor é única fonte de verdade do voto
         v
MANDATE PHASE
  Mayor eleito ativa projetos via ApprovalService
  Effect structs aplicados: multiplicadores de salário, impostos, ranking
  Cidade SENTE a diferença economicamente
         v
MANDATE EVALUATION (fim do ciclo)
  LegacyService avalia 3 dimensões
  Classifica mandato em tier
  Adiciona ao histórico acumulado do prefeito
  Aplica penalidade/recompensa de reputação
         v
NEXT CANDIDACY PHASE
  Ciclo recomeça com legado visível para eleitores
```

---

## 11. CONVENÇÕES DE CÓDIGO [INVARIANT]

### Naming
- `snake_case` - IDs persistidos, DataStore keys, project ids, ERROR_CODE em UPPER
- `camelCase` - variáveis Luau locais e parâmetros
- `PascalCase` - módulos, tipos, services

### Funções públicas
- TODA função pública tem bloco de comentário com: responsabilidade, parâmetros, retornos, edge cases tratados.
- Padrão obrigatório a seguir: `payPlayerWithTax` no JobService (documenta 5 caminhos de retorno).

### Deserialização de DataStore
- NUNCA aceitar input de DataStore sem sanitização.
- Helper de sanitização NUNCA lança exceção - sempre retorna valor válido ou default.
- Padrão: `sanitizeProjectIds` no ElectionService.

### Defensive defaults
- Preferir default seguro a strict failure em runtime de jogo.
- Perder uma taxa rara é melhor que travar um pagamento de salário.
- Log de warn quando defeito defensivo é acionado.

### Logs
- Prefixo obrigatório: `[MY CITY]`
- Formato de valor monetário: mostrar gross, tax e net - ex: `"earned 23 CC (gross 24 - 1 tax)"`

---

## 12. PROTOCOLO DE COMMITS [INVARIANT]

**Lei cardinal: um commit responde uma única pergunta de produto ou técnica.**

### Formato de mensagem
```
<arquivo|módulo>: <ação> (<contexto>)
```
Exemplos:
- `ElectionService: fix auto-vote guard (commit 1)`
- `TreasuryService: new isolated module with DataStore (commit 3)`
- `JobService: integrate 5% income tax via payPlayerWithTax (commit 4)`

### Antes de cada commit
1. `git diff` revisado linha por linha
2. Protocolo de teste no Studio executado (seção 7)
3. Confirmar que nenhum invariant da seção 6 foi violado

### Push schedule [PRODUCT]
- Push agendado aos sábados (nunca durante semana de trabalho da empresa)
- Commits locais em branches derivadas de main preservadas até push

### Resolução de conflito: push schedule vs comando atual v2.1

Quando o autor ou o prompt da sessão disser explicitamente `commit and push`, essa instrução sobrescreve o push schedule. Caso contrário, commitar localmente e preservar para o push de sábado.

Nunca assumir push automático se o comando atual não pediu. Nunca bloquear push se o comando atual pediu claramente `commit and push`, salvo se houver working tree suja não relacionada, teste falhando, conflito de branch ou risco de perda de commits locais.

### Working tree
- SEMPRE verificar working tree limpo antes de trocar de branch
- SEMPRE rodar `git log --all` após operações grandes (lição do incidente TreasuryService)

---

## 13. ROADMAP OFICIAL (pós commit 7) [ROADMAP]

### Sprint 1 - Fechar o Loop Político [INTOCÁVEL - ver REGRA DE FOCO]
- **Commit 8:** ElectionUI cliente - painel visual de seleção de 3 projetos. Validação client-side é APENAS UX (feedback rápido); validação real está no servidor (commit 6/7).
- **Commit 9:** ApprovalService - lê projectIds do mayor eleito, aplica effect structs aos services existentes. Inclui swap de projeto durante mandato.
- **Commit 10:** Painel de transparência cidadão - tesouro da cidade, projeto ativo, ledger de transações.

### Sprint 2 - Duas Cidades Reais
- **Commit 11:** Identidade de Solara - jobs favorecidos, multiplicadores econômicos regionais, flavor visual.
- **Commit 12:** CityIdentityService - motor de interdependência. Trade Deals têm consequência econômica mensurável.
- **Commit 13:** Eventos de Solara - turismo natural, bônus de cross-city trade quando deal ativo.

### Sprint 3 - Economia de Status Real
- **Commit 14:** Custo de reputação para ações políticas (iniciar impeachment, propor trade, vetar projeto).
- **Commit 15:** Decay de reputação por inatividade (evitar inflação de status).
- **Commit 16:** LegacyService - avaliação automática de mandato, tier de classificação, histórico acumulado.
- **Commit 17:** Penalidade pós-impeachment segmentada por cidade (substitui regra de 7 dias único).

### Sprint 4 - Polimento e Escala
- **Commit 18:** Suite de testes unitários para funções puras (sanitizers, validators, calculators).
- **Commit 19:** NOTES.md vivo + ADRs para decisões arquiteturais grandes.
- **Commit 20+:** Features sazonais, novos projetos do catálogo, cidades 3 e 4.

---

## 14. SLASH COMMANDS DISPONÍVEIS

Estes comandos estão em `.claude/commands/` e devem ser usados em cada sessão relevante.

### Fallback obrigatório v2.1

Se um slash command citado aqui não existir em `.claude/commands/`, o Claude Code NÃO deve fingir que executou. Deve informar que o comando está ausente e executar a análise manualmente seguindo o mesmo protocolo descrito pelo nome do comando.

Exemplo: se `/remote-audit` não existir, fazer manualmente a auditoria de chamadores, payload, validação server-side, rate limit e risco de exploit.

### Pensamento e ideação
- **`/think [problema]`** - Pensamento estruturado: objetivo, alternativas, riscos, recomendação
- **`/brainstorm [objetivo]`** - 10 ideias classificadas por impacto e custo

### Code review e desenvolvimento
- **`/review-service [nome]`** - Análise profunda de service: o que faz, problemas, sugestões
- **`/new-service [nome]`** - Scaffolding de novo service seguindo padrões do projeto
- **`/new-mission [job] [local]`** - Scaffolding completo de nova missão

### Auditoria de produção (NOVOS - v2.0)
- **`/remote-audit [nome]`** - Audita Remote: chamadores, payload, validação server-side, risco de exploit
- **`/datastore-audit [service]`** - Audita persistência: schema, defaults, sanitizers, risco de migração
- **`/ui-flow [feature]`** - Planeja UI: entrada, loading, success, error, feedback, integração com Remotes

### Análise de sistemas
- **`/balance [sistema]`** - Análise de balanceamento com simulação de impacto
- **`/audit-loop [tipo]`** - Auditoria de gameplay loop (existe? sentido? profundidade? quebra onde?)

---

## 15. DECISÕES DE PRODUTO DOCUMENTADAS [PRODUCT]

Estas decisões foram tomadas pelo autor e NÃO devem ser "corrigidas" como bugs:

| Decisão | Justificativa |
|---------|---------------|
| Daily missions NÃO são taxadas | Missões são bônus, não salário regular |
| Passive income NÃO é taxado | Incentivo a investimento em propriedades |
| Apenas runWorkLoop é taxado | Imposto incide sobre renda do trabalho formal |
| Threshold de impeachment = 70% | Evitar impeachments fáceis; mandato tem peso |
| projectIds é parâmetro opcional no Nominate | Backward compat com cliente do commit 2 |
| Ledger de tesouro limitado a 50 entradas | Performance; histórico recente é suficiente para UI |
| Mandato estendido automaticamente sem candidatos | Evitar cidade sem governo; gameplay > realismo |
| Solara e Ironholm com identidades distintas | Escolha de cidade deve ser estratégica, não cosmética |
| Nenhuma cidade pode ser autossuficiente | Interdependência é o motor político do jogo |
| Bloqueio pós-impeachment é por cidade, não global | Permite redenção em outra cidade; punição segmentada |

---

## 16. RISCOS ATIVOS E MITIGAÇÕES [ROADMAP]

| Risco | Severidade | Status | Mitigação |
|-------|-----------|--------|-----------|
| UI de campanha sem painel de projetos | Alta | WIP -> Commit 8 | Servidor já pronto; só falta cliente |
| ApprovalService não existe | Crítica | TODO -> Commit 9 | Loop político não fecha sem ele |
| Solara com 0 pontos / cidade vazia | Alta | TODO -> Sprint 2 | Identidade regional + jobs favorecidos |
| Reputação só sobe, nunca desce | Média-Alta | TODO -> Sprint 3 | Custo político + decay temporal |
| Sem testes automatizados | Baixa agora | TODO -> Sprint 4 | Funções puras são candidatas ideais |
| Remotes sem rate limit explícito | Alta | TODO -> commit separado de hardening | Aplicar padrão da seção 3 aos Remotes afetados; não inflar Commit 8 com auditoria global |
| NOTES.md não existe | Média | Bloqueado por bug de markdown rendering | Este CLAUDE.md substitui parcialmente |
| Branches com cherry-picks manuais | Baixa | Consciente | Branch agregadora antes do push de sábado |

---

## 17. COMO TRABALHAR NESTE PROJETO [INVARIANT]

### Antes de começar qualquer sessão
1. Ler este CLAUDE.md inteiro (feito automaticamente pelo Claude Code)
2. Identificar o nível de cada regra ([INVARIANT] / [PRODUCT] / [ROADMAP]) antes de propor mudança
3. Rodar `git status` e `git log --oneline -10`
4. Confirmar qual commit está sendo trabalhado
5. **Lembrar da REGRA DE FOCO** se estiver no Sprint 1

### Antes de modificar qualquer service
1. Verificar se está em ESTÁVEIS, CORE POLÍTICO ou PENDENTES (seção 5)
2. CORE POLÍTICO: exige protocolo de teste completo (seção 7)
3. SAGRADO (PlayerDataService, init.server.luau): exige aprovação explícita do autor

### Antes de criar novo service
1. Rodar `/new-service` para seguir o padrão
2. Criar sem consumidores primeiro (testar em isolamento)
3. Integrar em commit separado com teste de runtime

### Antes de criar/modificar Remote
1. Rodar `/remote-audit` no Remote afetado
2. Aplicar o padrão obrigatório da seção 3
3. Definir ERROR_CODEs específicos no catálogo
4. Confirmar rate limiting

### Antes de mudar persistência (DataStore)
1. Rodar `/datastore-audit` no service afetado
2. Aplicar o checklist de migração da seção 4
3. Confirmar que sanitizer cobre o novo caso
4. NUNCA renomear key sem ADR documentado

### Ao identificar um problema
1. Rodar `/think [problema]` para estruturar antes de codar
2. Identificar o nível das regras envolvidas ([INVARIANT] / [PRODUCT] / [ROADMAP])
3. Verificar se solução viola algum invariant da seção 6
4. Verificar se contradiz alguma decisão de produto da seção 15

---

## 18. PROTOCOLO DE EXECUÇÃO PARA CLAUDE CODE [INVARIANT]

Para qualquer tarefa de código, o Claude Code deve seguir este fluxo operacional. Este protocolo existe para transformar intenção em execução segura, sem refactor acidental e sem mudanças genéricas.

### 18.1 Antes de editar
1. Diagnosticar o problema com base nos arquivos reais, não em suposição.
2. Rodar `git status --short`.
3. Rodar `git branch --show-current`.
4. Rodar `git log --oneline --decorate --graph --all -n 20` quando houver commits locais, cherry-pick, branches ou integração pendente.
5. Declarar quais arquivos pretende tocar.
6. Confirmar se a tarefa pertence a Sprint 1 ou se é distração fora do loop político.

### 18.2 Durante a edição
1. Manter o menor escopo possível.
2. Não reescrever arquivo inteiro quando patch cirúrgico resolve.
3. Não refatorar código fora do problema pedido.
4. Preferir mudanças aditivas quando possível.
5. Não alterar DataStore key, schema persistido, Remote contract ou service core sem justificar explicitamente.
6. Preservar compatibilidade com cliente antigo quando o servidor já foi desenhado para isso.

### 18.3 Após editar
1. Revisar `git diff` linha por linha.
2. Executar validação disponível no repo.
3. Se não houver validação automatizada, declarar isso claramente.
4. Quando a mudança envolver Roblox runtime, fornecer checklist de teste no Studio.
5. Reportar exatamente:
   - arquivos alterados;
   - comportamento alterado;
   - comportamento preservado;
   - testes executados;
   - riscos restantes;
   - commit hash, se commit foi criado.

### 18.4 Regra anti-invenção

Claude Code não deve inventar estado do projeto. Antes de afirmar que algo existe, está commitado, está limpo, está em determinada branch ou foi enviado ao GitHub, deve verificar com comandos reais.

Frases proibidas sem verificação:
- "já está no GitHub";
- "working tree está limpo";
- "não há conflito";
- "o commit anterior existe";
- "o build passou".

### 18.5 Regra anti-overengineering

Se a tarefa puder ser resolvida com 30 linhas, não criar 300. Se puder ser resolvida em um arquivo, não tocar cinco. Se exigir arquitetura nova, explicar por que a arquitetura existente não basta.

O objetivo é construir MY CITY com profundidade, não com excesso.

---

*Este documento é uma obra viva. Atualizar após cada decisão arquitetural significativa.*
*Versão atual: 2.1 - Blindagem de Produção + Execução Cirúrgica*
*Próxima atualização prevista: após Commit 9 (ApprovalService), ou antes se o fluxo real do Claude Code revelar nova ambiguidade operacional.*
