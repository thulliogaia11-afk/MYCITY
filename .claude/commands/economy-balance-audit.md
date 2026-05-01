# /economy-balance-audit — Auditoria de Economia

USO: /economy-balance-audit [feature]

Objetivo: verificar se a feature cria inflação, exploração, progressão quebrada ou desequilíbrio entre jogadores novos e veteranos.

## Princípio
Em MY CITY, economia não é só número. **Economia é política.** Se o dinheiro quebra, a eleição quebra. Se o tesouro quebra, a confiança quebra.

## Fluxo econômico
- Fonte de dinheiro.
- Saída de dinheiro.
- Frequência de recompensa.
- Cooldown.
- Risco de spam e duplicação.
- Risco de exploração client-side.
- Impacto no tesouro e na reputação.

## Progressão prática
- Quanto tempo um jogador novo leva para comprar o primeiro item útil?
- Quanto tempo até conseguir participar de política com dignidade?
- Quanto tempo até sentir progresso real?
- Jogador rico domina tudo?
- Jogador novo fica bloqueado cedo demais?
- Existe sink suficiente para dinheiro acumulado?
- O imposto parece consequência política ou punição injusta?

## Regras sagradas
- Daily missions não são taxadas.
- Passive income não é taxado.
- Apenas runWorkLoop é taxado.
- Cliente nunca decide recompensa.
- Servidor recalcula reward, taxa, saldo e elegibilidade.
- Treasury failure não deve cobrar depois taxa perdida.

## Valores de referência atuais
- Imposto de renda: 5% sobre runWorkLoop
- Factory Worker: 24 CC brutos, 1 CC imposto, 23 CC líquidos
- LuxuryVilla passive income: 25 CC por ciclo
- Mission reward (Factory Worker): 45 CC + 7 reputação
- Impeachment threshold: 70%
- Dismissal cooldown: 6 dias

## Formato obrigatório

### Veredito
SAUDÁVEL | AJUSTAR NÚMEROS | RISCO DE INFLAÇÃO | RISCO DE FRUSTRAÇÃO | RISCO DE EXPLOIT | BLOQUEADO

### Money flow
Diagrama textual de fontes e sinks.

### Tempo até progresso
- Primeiro item útil:
- Participação política digna:
- Progresso real sentido:

### Riscos econômicos
| Severidade | Risco | Cenário | Impacto |
|------------|-------|---------|---------|

### Impacto político
Análise específica sobre tesouro, eleição e reputação.

### Correção mínima
Ajuste pequeno com valores propostos e justificativa.

### Critério de validação
Como saber se o ajuste funcionou após deploy.
