# /tech-debt — Auditoria de Dívida Técnica

USO: /tech-debt [arquivo, service ou feature]

Objetivo: auditar dívida técnica real, sem transformar preferências pessoais em prioridade.

## IMPORTANTE
- Não corrigir automaticamente.
- Não propor refactor grande sem necessidade.
- Não mexer em services estáveis sem motivo.
- Priorizar dívida que afeta segurança, DataStore, Remotes, loop político ou perda de dados.

## Tipos de dívida
- Bug real | Risco técnico | Dívida futura | Polimento premium | Preferência estética

## Prioridade
- **P0:** exploit, perda de dados ou quebra de boot.
- **P1:** bloqueia loop político ou feature core.
- **P2:** aumenta risco futuro.
- **P3:** limpeza útil.
- **P4:** gosto pessoal; não fazer agora.

## Formato obrigatório

### Veredito
LIMPO | DÍVIDA CONTROLADA | DÍVIDA RELEVANTE | BLOQUEADOR

### Dívidas encontradas
| Prioridade | Tipo | Arquivo | Problema | Por que importa | Correção mínima |
|------------|------|---------|----------|-----------------|-----------------|

### Não corrigir agora
Listar itens que parecem dívida, mas não valem o risco neste momento.

### Próximo passo
Uma única correção recomendada.
