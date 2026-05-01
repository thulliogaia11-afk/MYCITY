# /ui-flow — Planejamento de UI

USO: /ui-flow [nome da feature]

Objetivo: planejar UI antes de codar, com foco em clareza para o jogador, segurança client/server, mobile-first e alinhamento com a visão central do MY CITY.

## IMPORTANTE
- Este comando é PLANEJAMENTO.
- Não modificar arquivos sem autorização explícita.
- Não criar UI genérica.
- Validação client-side é apenas UX; segurança real fica no servidor.
- O client nunca calcula Money, XP, Reputation, Treasury, Vote result ou Project effect.

## Contexto obrigatório
O servidor já sabe receber e validar 3 projectIds, mas o ElectionUI ainda não tem painel visual de seleção de projetos.

**Commit 8 não é apenas uma tela. É o nascimento da promessa pública.**
A UI de campanha deve comunicar: *"Escolha suas promessas públicas. A cidade vai lembrar."*

## Objetivo de produto
- Qual desejo esta UI serve? Visual, progressão ou domínio social?
- Qual decisão do jogador esta UI torna mais clara?
- Esta UI fecha qual loop do jogo?
- O jogador entende por que esta ação importa?
- A cidade parece mais viva por causa desta UI?

## Estados obrigatórios
- Initial | Loading | Empty state | Success | Error | Disabled / blocked
- Stale state quando fase política/cidade muda
- Double-click prevention | Server timeout / retry

## Empty states
- E se não houver candidatos, projetos ou ledger ainda?
- Lista vazia válida vs erro?
- Cliente antigo sem dados novos?

## Wireframe textual obrigatório
Header, contexto, lista principal, ação primária, ação secundária, estado público, loading, empty state, erro, mobile portrait, mobile landscape.

## Mobile-first e performance
- Tap targets mínimos de 44x44 px.
- Texto legível sem zoom, portrait e landscape.
- ScrollingFrame quando necessário.
- Botão primário sempre visível.
- Não exige hover para informação essencial.
- UI leve para mobile (sem efeitos pesados).
- Confirmação para ações irreversíveis.

## Error states
Catálogo canônico vive no CLAUDE.md, seção "Catálogo Central de ERROR_CODEs".

| Error code | Mensagem para jogador | Ação disponível |
|------------|-----------------------|-----------------|
| INVALID_PAYLOAD | Algo deu errado. Tente novamente. | Fechar / tentar de novo |
| INVALID_PHASE | Esta ação não está disponível agora. | Ver fase atual |
| NOT_ELIGIBLE | Você ainda não pode fazer isso. | Ver requisitos |
| INSUFFICIENT_REPUTATION | Você precisa de mais reputação. | Ver como ganhar |
| INSUFFICIENT_FUNDS | Você não tem CityCash suficiente. | Ir trabalhar |
| COOLDOWN_ACTIVE | Aguarde antes de tentar novamente. | Ver tempo restante |
| RATE_LIMITED | Calma! Espere um momento. | Tentar depois |
| PROJECT_INVALID | Projeto inválido ou indisponível. | Recarregar lista |
| PROJECT_DUPLICATE | Escolha 3 projetos diferentes. | Ajustar seleção |
| CITY_MISMATCH | Esta ação pertence a outra cidade. | Atualizar cidade |
| ALREADY_VOTED | Você já votou nesta eleição. | Ver candidatos |
| SELF_VOTE_BLOCKED | Você não pode votar em si mesmo. | Escolher outro |
| INTERNAL_ERROR | Erro inesperado. Tente novamente. | Tentar depois |

## Integração com Remotes
O client envia intenção. O servidor valida. A UI usa apenas resposta do servidor para atualizar estado.

## Estados especiais
- E se a fase política mudar com UI aberta?
- E se o jogador trocar de cidade ou perder elegibilidade?
- E se o prefeito for impeached?
- E se o jogador desconectar durante chamada?
- E se o jogador abrir duas janelas da mesma UI?

## Identidade do MY CITY
- Política deve parecer importante, não menu genérico.
- Projetos devem parecer promessas de campanha.
- Impeachment deve parecer ação pesada, não botão casual.

## Formato obrigatório

### Veredito da UI
PRONTA PARA IMPLEMENTAR | PRECISA DE AJUSTES | BLOQUEADA

### Objetivo de produto
| Pergunta | Resposta |
|----------|----------|
| Desejo servido | |
| Loop que fecha | |
| Decisão do jogador | |
| Risco de confusão | |

### Fluxo proposto
Entrada → Estado inicial → Loading → Ação → Resposta servidor → Feedback → Próximo estado

### Wireframe textual
Esquema completo.

### Estados obrigatórios
| Estado | Trigger | Mensagem | Ação disponível |
|--------|---------|----------|-----------------|

### Remote contract
Payload mínimo + resposta esperada.

### Riscos UX
| Severidade | Problema | Impacto | Correção |
|------------|----------|---------|----------|

### Implementação mínima
- Arquivo client:
- Remote:
- Services:
- Componentes Roblox:
- Teste manual:

### O que NÃO deve ser alterado
Invariants relevantes.

### Próximo passo
Uma única ação pequena e segura.
