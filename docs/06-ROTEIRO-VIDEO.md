# Roteiro do vídeo (até 20 min · alvo: ~18 min)

> Cada bloco: [tempo] · O QUE MOSTRAR na tela · O QUE DIZER (resumo falável).
> Os ✔ marcam checkpoints literais do enunciado — nenhum pode faltar.
> Grave com os terminais já abertos e comandos no histórico (seta ↑) pra não
> digitar ao vivo. Deixe `kubectl get hpa -w` rodando num terminal separado
> ANTES do bloco 5.

## Bloco 0 — Abertura [0:30]
**Tela**: slide simples ou README com nome do projeto e integrantes.
**Fala**: "Tech Challenge Fase 2 — evolução do ToggleMaster de monolito para
5 microsserviços em Docker e Kubernetes no AWS EKS, usando conta AWS Academy."

## Bloco 1 — Arquitetura [2:00]
**Tela**: diagrama (o mesmo gerado no chat serve; exporte como imagem).
**Fala**: os 5 serviços e o papel de cada um; auth/flag/targeting com RDS
próprio; evaluation como hot path com Redis; evaluation publica evento no SQS
e o analytics consome e grava no DynamoDB. Cliente entra pelo Nginx Ingress.

## Bloco 2 — Ambiente local ✔ [2:30]
**Tela**: terminal na pasta `local/`.
**Comandos**: `docker compose up -d --build` (já rodado antes; mostre) →
`docker compose ps` com os **9 containers Up** ✔ → um `curl localhost:8004/health`.
**Fala**: "5 aplicações + 2 Postgres + Redis + DynamoDB Local. O compose prova
o ecossistema completo rodando localmente antes da nuvem."

## Bloco 3 — Infra provisionada na AWS ✔ [2:00]
**Tela**: Console AWS — EKS (cluster + node group com LabRole e auto scaling
min/desejado/máx) ✔ → RDS (3 instâncias) → ElastiCache → SQS → DynamoDB.
**Fala**: 1 frase por recurso. "Cluster e node group usam a LabRole — única
role permitida no Academy."

## Bloco 4 — Pods e Ingress ✔ [2:30]
**Tela**: terminal.
**Comandos**:
- `kubectl get pods -n techchallenger` → **5 microsserviços Running** ✔
- `kubectl get ingress -n techchallenger`
- `curl http://$LB/auth/health` (200) e `curl http://$LB/flags` (401 — "o 401
  prova que o Ingress roteou até o serviço e a autenticação está ativa") ✔
- Fluxo rápido: criar key → criar flag → `curl /evaluate` retornando true ✔
**Fala**: rotas do Ingress (auth com rewrite, /flags e /rules diretos,
/ catch-all no evaluation).

## Bloco 5 — Escalabilidade do evaluation-service ✔ [3:00]
**Tela**: 2 terminais lado a lado — esquerda `kubectl get hpa -n techchallenger -w`,
direita a carga.
**Comandos** (direita): `hey -z 90s -c 50 "http://$LB/evaluate?user_id=u1&flag_name=checkout_v2" -H "Authorization: Bearer $TM_KEY"`
(sem `hey`: loop com `ab` ou `while true; do curl ...; done` em 2-3 abas).
**Mostrar**: TARGETS passando de 70% → REPLICAS subindo → `kubectl get pods` com pods novos ✔.
**Fala**: "HPA por CPU, alvo 70%, mín 2 máx 6. A carga elevou a CPU média e o
HPA adicionou réplicas."

## Bloco 6 — Fila SQS + analytics + DynamoDB ✔ [3:00]
**Tela**: terminal + Console (fila e tabela).
**Comandos**:
```bash
for i in $(seq 1 200); do aws sqs send-message \
  --queue-url $SQS_URL \
  --message-body "{\"user_id\":\"u$i\",\"flag_name\":\"checkout_v2\",\"result\":true,\"timestamp\":\"2026-07-08T12:00:00Z\"}" \
  >/dev/null & done; wait
```
✔ envio manual de mensagens → `kubectl get hpa analytics-service-hpa -w`
(CPU sobe ao processar; réplicas aumentam) ✔ →
`kubectl logs deploy/analytics-service -n techchallenger --tail=20` ("salvo no
DynamoDB") → `aws dynamodb scan --table-name ToggleMasterAnalytics --max-items 5`
ou Console mostrando os itens ✔.
**Fala**: "O consumo em lote eleva a CPU do worker; o HPA reage. É o
workaround do Academy — explico já por quê."

## Bloco 7 — Explicações obrigatórias ✔ [2:30]
**Tela**: pode voltar ao diagrama.
**Fala** (3 partes, todas exigidas no enunciado):
1. **Limitações do Academy / desafios** ✔: "Sem criar roles → sem IRSA → pods
   herdam a LabRole do nó via metadata da instância. Nosso maior desafio real:
   os pods não alcançavam esse metadata (hop-limit=1) e o SQS falhava com
   NoCredentialProviders; corrigimos ajustando o hop-limit das instâncias.
   Também encontramos e corrigimos uma rota de criação de chaves sem
   autenticação no auth-service e um rewrite incorreto no Ingress."
2. **Escalabilidade: HPA-CPU vs KEDA** ✔: "O ideal seria KEDA lendo a
   profundidade da fila e escalando inclusive de zero — mas KEDA exige IRSA.
   Por isso HPA por CPU: quando a fila enche, o worker processa mais, a CPU
   sobe e o HPA escala. Indireto, mas funcional e compatível com o Academy."
3. **Os 3 data stores** ✔: "RDS/PostgreSQL para dados relacionais e
   transacionais (chaves, flags, regras); ElastiCache/Redis como cache de
   baixíssima latência no hot path; DynamoDB para alto volume de escrita de
   eventos com consulta simples por chave. Cada um no papel em que é melhor."

## Bloco 8 — Encerramento [0:30]
**Fala**: recap de 2 frases + "links do repositório e deste vídeo no relatório
de entrega". Fim.

---
**Checklist final antes de subir o vídeo** — confira que TODOS os ✔ aparecem:
compose 9 up · cluster no console · 5 pods · curl via LB · carga+HPA evaluation ·
mensagens manuais SQS · HPA analytics · dados no DynamoDB · explicação
arquitetura+desafios · justificativa HPA-CPU · propósito dos 3 data stores.
