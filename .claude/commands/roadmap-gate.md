# /roadmap-gate — Decisão de Prioridade

USO: /roadmap-gate [feature ou pedido]

Objetivo: decidir se uma feature deve ser feita agora, depois, ou rejeitada por desalinhamento com o estado atual do MY CITY.

## Contexto obrigatório
**MY CITY não deve virar uma coleção de sistemas soltos.**

Loop central: cidade → política → promessa → voto → mandato → dinheiro público → projeto → consequência → reputação → memória histórica.

Curto prazo recomendado:
- Commit 8: Campaign Pledge UI com seleção de 3 promessas públicas.
- Commit 9: ApprovalService / execução real dos projetos.
- Commit 10: penalidade de reputação por prefeito inativo + ban pós-impeachment.
- Commit 11: painel de transparência cidadã.

## Classificar a feature
- Core político | Core econômico | UI necessária | Transparência cidadã
- Status / reputação | Cidade / identidade | Conteúdo cosmético | Nice-to-have | Distração

## Perguntas de gate
- Ajuda a fechar os Commits 8-11?
- Fecha ou fortalece o loop político?
- Melhora retenção central?
- Reduz risco técnico?
- Cria dívida técnica?
- Mexe em service sagrado?
- Pode esperar sem prejudicar o produto?

## Decisão permitida
FAZER AGORA | PLANEJAR AGORA, FAZER DEPOIS | ADIAR | REJEITAR POR ENQUANTO

## Formato obrigatório

### Decisão
Uma das quatro opções.

### Justificativa
Máximo 5 linhas.

### Riscos
| Risco | Impacto | Mitigação |
|-------|---------|-----------|

### Melhor momento
Commit/sprint recomendado.

### Próxima ação
Uma única ação pequena, segura e testável.
