# /implement-surgical — Plano de Implementação Cirúrgica

USO: /implement-surgical [feature ou bugfix]

Objetivo: transformar uma feature aprovada em um plano de implementação pequeno, seguro e testável.

## IMPORTANTE
- Não implementar ainda se o escopo não estiver fechado.
- Não inventar arquivos, services, remotes ou paths.
- Se um arquivo esperado não existir, declarar NOT FOUND e parar antes de criar arquitetura.
- Não alterar DataStore keys.
- Não tocar em arquivos fora da lista permitida.
- **Não criar arquivos novos a menos que estejam explicitamente listados em "Arquivos permitidos".**
- **Helpers auxiliares devem ser inline ou justificados em comentário antes do plano.**
- Se surgir necessidade de arquivo fora da lista, parar e pedir nova decisão.

## Pré-condições
Gates a verificar antes de implementar:
- Roadmap gate aprovado quando aplicável.
- UI flow aprovado quando aplicável.
- Game feel audit considerado quando aplicável.
- Economy audit considerado se tocar dinheiro/reputação/tesouro.
- Remote audit considerado se tocar Remote.
- Political loop audit considerado se tocar política.
- Datastore audit considerado se tocar persistência.

## Escopo fechado
- Arquivos permitidos para alterar.
- Arquivos proibidos de alterar.
- Services afetados.
- Remotes afetados.
- DataStores afetados.
- Shared modules afetados.

## Plano mínimo
1. Mudança mínima.
2. Validação local/manual.
3. Revisão de diff.
4. Commit pequeno.

Se mais de 4 passos forem necessários, considerar dividir em commits separados.

## Validação manual
Testar pelo menos:
- Player novo.
- Player antigo com dados salvos.
- Player sem cidade.
- Player prefeito (se aplicável).
- Player candidato (se aplicável).
- Player votante (se aplicável).
- Mobile portrait + landscape.
- Desconexão durante chamada.
- Cliente antigo (se Remote envolvido).

## Rollback plan
- Como reverter (git revert, git reset, ou re-edição).
- Quais arquivos voltar.
- Como confirmar que o jogo voltou ao estado anterior.

## Prompt final para Cursor/Codex/Claude Code
Bloco pronto para copiar:
- Objetivo
- Escopo
- Arquivos permitidos
- Arquivos proibidos
- Invariants a respeitar
- Validação esperada
- Commit and push (se autorizado)

## Formato obrigatório

### Veredito
PRONTO PARA IMPLEMENTAR | PRECISA FECHAR ESCOPO | BLOQUEADO

### Escopo fechado
Resumo do que será feito.

### Arquivos permitidos
Lista exata.

### Arquivos proibidos
Lista exata, com razão.

### Plano cirúrgico
Passos numerados.

### Testes manuais
Lista de cenários a validar.

### Rollback
Plano de reversão.

### Prompt final
Bloco pronto para Cursor/Codex/Claude Code.

### Commit recomendado
Mensagem no padrão: `<arquivo|módulo>: <ação> (<contexto>)`
