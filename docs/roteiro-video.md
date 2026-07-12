# Roteiro do vídeo — Tech Challenge Fase 2 (alvo: 15-18 min)

Antes de gravar, deixa pronto:
- Dois terminais abertos (um pra comandos, um pra `watch`/logs)
- Console AWS logado nas abas: EKS, RDS, ElastiCache, SQS, DynamoDB
- Variáveis setadas no terminal:
```bash
LB=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
TM_KEY=<sua chave tm_key_...>
SQS_URL=https://sqs.us-east-1.amazonaws.com/007188159471/techchallenger-evaluation-events
```

---

## 1. Abertura (30s)
Fala: "Tech Challenge Fase 2. O ToggleMaster saiu de um monolito pra 5 microsserviços — auth, flag, targeting, evaluation e analytics — rodando em Docker local e em Kubernetes no EKS, usando AWS Academy."

## 2. Local — docker compose (2 min)
```bash
cd local
docker compose up -d
docker compose ps
```
Mostra os 9 containers Up (5 apps + 3 Postgres + Redis + DynamoDB local).
Fala: "Todo o ecossistema roda local antes da nuvem. Cada serviço tem seu Dockerfile multi-stage, e o compose sobe apps e bancos com healthcheck controlando a ordem de subida."

## 3. Infra na AWS (2 min)
Passeia pelo Console mostrando, sem demorar:
- EKS: cluster `techchallenger` Active, node group com LabRole, scaling 1/2/4
- RDS: as 3 instâncias (auth-db, flags-db, targeting-db)
- ElastiCache: techchallenger-redis
- SQS: fila techchallenger-evaluation-events
- DynamoDB: tabela ToggleMasterAnalytics

Fala: "Cluster criado pelo Console com a LabRole — no Academy não dá pra criar role nova, então cluster e nodes usam a LabRole. Imagens publicadas no ECR, um repositório por serviço."

## 4. Pods e Ingress (2 min)
```bash
kubectl get nodes
kubectl get pods -n techchallenger
kubectl get ingress -n techchallenger
```
Mostra os 5 serviços Running.
```bash
curl -i http://$LB/auth/health
```
Fala: "Nginx Ingress Controller criou um Load Balancer na AWS. As rotas: /auth vai pro auth-service com rewrite, /flags e /rules direto, e a raiz cai no evaluation-service."

## 5. Fluxo completo (3 min)
```bash
curl -s -X POST http://$LB/auth/admin/keys -H "Authorization: Bearer admin-secreto-123" -H "Content-Type: application/json" -d '{"name":"video"}'
```
Copia a chave, exporta no TM_KEY.
```bash
curl -s -X POST http://$LB/flags -H "Authorization: Bearer $TM_KEY" -H "Content-Type: application/json" -d '{"name":"demo_video","is_enabled":true}'
curl -s "http://$LB/evaluate?user_id=user-1&flag_name=demo_video" -H "Authorization: Bearer $TM_KEY"
```
Fala: "O evaluation valida a chave no auth, busca a flag no flag-service, cacheia no Redis e responde. Em paralelo, publica o evento na fila SQS."

## 6. HPA — evaluation sob carga (3 min)
Terminal 2:
```bash
watch -n 2 "kubectl get hpa -n techchallenger; echo; kubectl get pods -n techchallenger -l app=evaluation-service"
```
Terminal 1 — gera carga:
```bash
for i in $(seq 1 8); do ( while true; do curl -s "http://$LB/evaluate?user_id=load$i&flag_name=demo_video" -H "Authorization: Bearer $TM_KEY" >/dev/null; done ) & done
```
Mostra o CPU passando de 70% e as réplicas subindo de 2 pra 3, 4...
Fala: "HPA por CPU, alvo 70%, mínimo 2 e máximo 6. A carga sobe, o Metrics Server reporta, o HPA escala."
Para a carga:
```bash
kill $(jobs -p)
```

## 7. SQS → analytics → DynamoDB (3 min)
Envia mensagens manuais na fila:
```bash
for i in $(seq 1 100); do aws sqs send-message --queue-url $SQS_URL --message-body "{\"user_id\":\"u$i\",\"flag_name\":\"demo_video\",\"result\":true,\"timestamp\":\"2026-07-12T12:00:00Z\"}" >/dev/null & done; wait
```
No terminal 2, troca o watch pro HPA do analytics:
```bash
watch -n 2 "kubectl get hpa analytics-service-hpa -n techchallenger"
```
Mostra o CPU do analytics subindo com o consumo e escalando.
```bash
kubectl logs -n techchallenger deployment/analytics-service --tail=10
aws dynamodb scan --table-name ToggleMasterAnalytics --region us-east-1 --max-items 5
```
Mostra os itens gravados (ou abre a tabela no Console).
Fala: "O analytics consome a fila em lote e grava no DynamoDB. Como o Academy não permite IRSA, o KEDA não funciona — então o HPA por CPU é o workaround: fila enche, worker processa mais, CPU sobe, HPA escala."

## 8. Fechamento — explicações exigidas (2-3 min)
Fala, com o diagrama ou o Console na tela:

**Limitações do Academy e desafios reais:**
"Sem criar roles, tudo roda com a LabRole. Os pods herdam a permissão do nó via metadata da instância EC2 — e o maior problema que enfrentamos foi exatamente esse: o hop-limit do metadata bloqueava os containers de pegar credencial, gerando NoCredentialProviders no SQS. Corrigimos ajustando o hop-limit das instâncias pra 2. Também liberamos as portas 5432 e 6379 no security group pra VPC, corrigimos uma dependência faltante no analytics e uma rota sem autenticação no auth-service."

**Escalabilidade — HPA vs KEDA:**
"O ideal em conta pessoal seria KEDA lendo a profundidade da fila e escalando até de zero. No Academy o KEDA depende de IRSA, então usamos HPA por CPU nos dois serviços — funciona porque o consumo da fila vira CPU."

**Os 3 data stores:**
"RDS pra dado relacional e transacional — chaves, flags e regras. ElastiCache Redis como cache de baixa latência no hot path de avaliação. DynamoDB pra escrita de eventos em volume, consulta simples por chave. Cada um no papel certo."

Encerra: "Links do repositório e do vídeo estão no relatório de entrega. Obrigado."

---

## Checklist do enunciado (confere antes de subir o vídeo)
- [ ] compose com 9 containers
- [ ] cluster no Console
- [ ] kubectl get pods com os 5 serviços
- [ ] curl no Load Balancer
- [ ] carga + HPA do evaluation escalando
- [ ] mensagens manuais no SQS
- [ ] HPA do analytics reagindo
- [ ] itens no DynamoDB
- [ ] explicação: arquitetura + desafios/LabRole
- [ ] justificativa HPA por CPU vs KEDA
- [ ] diferença RDS vs ElastiCache vs DynamoDB
