# /notes-capture — Captura de Decisões Vivas

USO: /notes-capture [decisão, sessão ou feature]

Objetivo: capturar decisões vivas do projeto em formato seguro para documentação futura.

## IMPORTANTE
- Não criar arquivo automaticamente se o ambiente estiver com bug de markdown rendering.
- Se criar arquivo, pedir confirmação antes.
- Preferir produzir bloco pronto para colar em NOTES.md, ADR ou CLAUDE.md.
- Separar decisão de produto, decisão técnica e observação temporária.

## Classificar a informação
- Product decision
- Technical decision
- Operational lesson
- Known issue
- Risk
- Future idea
- Rejected idea
- Migration note

## Capturar
- Decisão tomada.
- Por que foi tomada.
- Alternativas consideradas.
- Risco aceito.
- Onde isso impacta o código.
- Quando revisar novamente.

## Formato obrigatório

### Tipo

### Decisão

### Justificativa

### Impacto técnico

### Impacto de produto

### Invariants relacionados

### Revisar quando

### Bloco pronto para NOTES.md
## [DATA] — [TÍTULO]
**Tipo:** [classificação]
**Decisão:** [resumo em uma frase]
**Contexto:** [por que foi necessário decidir]
**Alternativas consideradas:** [lista]
**Risco aceito:** [o que estamos abrindo mão]
**Impacto:** [onde no código isso vive]
**Revisar quando:** [trigger temporal ou de evento]
