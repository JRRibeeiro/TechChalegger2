# Passo a passo — do zip até o cluster rodando (v2, revisado)

> Toda etapa segue: o quê / por quê / onde / comandos / validação / erros comuns.
> Ordem importa — não pule a Etapa 3 (rebuild), ela destrava a 4.

## Pré-requisitos (uma vez)

- Repo `TechChalegger2` clonado localmente
- `kubectl` apontando pro cluster: `aws eks update-kubeconfig --name <cluster> --region us-east-1`
- AWS CLI com credenciais do Academy ativas
- Docker logado no Docker Hub (`docker login`) — vai precisar dar push

---

## Etapa 0 — Integrar o pacote no repo

**O quê**: extrair o zip por cima do repo (paths idênticos, substituição direta).
**Por quê**: sem isso, as correções não existem no seu projeto.
**Onde**: terminal, raiz do repo.

```bash
cd caminho/para/TechChalegger2
unzip -o ~/Downloads/togglemaster-fase2-correcoes.zip -d .
git diff --stat        # confira o que mudou antes de commitar
git add . && git commit -m "Fase 2: correções da revisão (analytics, HPA, ingress, secrets, namespace)" && git push
```

**Validação**: `git status` limpo; arquivos novos visíveis no GitHub.

---

## Etapa 1 — Credenciais SQS no EKS (P0 — bloqueador)

**O quê**: destravar o `NoCredentialProviders` do evaluation-service.
**Por quê**: sem isso nenhum evento chega na fila — trava a demo de analytics inteira.
**Onde**: terminal (kubectl + aws).
**Guia completo**: `docs/03-RUNBOOK-CREDENCIAIS-SQS.md` (diagnóstico de 2 min + 2 caminhos). Resumo do caminho provável:

```bash
kubectl get nodes -o jsonpath='{.items[*].spec.providerID}'   # extraia os i-...
aws ec2 modify-instance-metadata-options --instance-id i-XXXX \
  --http-put-response-hop-limit 2 --http-endpoint enabled     # repita por nó
```

**Validação**: após a Etapa 6, logs do evaluation mostram `Evento de avaliação enviado para SQS`.
**Erro comum**: LabRole sem permissão pra esse comando → fallback com credenciais temporárias no Secret (passo 3 do runbook).

---

## Etapa 2 — Tabela DynamoDB (P0)

**O quê**: garantir que `ToggleMasterAnalytics` (PK `event_id`) existe na AWS.
**Por quê**: sem tabela, todo `put_item` falha com `ResourceNotFoundException`.
**Onde**: terminal (AWS CLI) ou Console → DynamoDB.

```bash
aws dynamodb describe-table --table-name ToggleMasterAnalytics --region us-east-1 \
  || aws dynamodb create-table --table-name ToggleMasterAnalytics \
       --attribute-definitions AttributeName=event_id,AttributeType=S \
       --key-schema AttributeName=event_id,KeyType=HASH \
       --billing-mode PAY_PER_REQUEST --region us-east-1
```

**Validação**: `"TableStatus": "ACTIVE"`.

---

## Etapa 3 — Corrigir código + REBUILD e PUSH (novo — não pule!)

**O quê**: duas correções de código-fonte e republicação das imagens:
1. `analytics-service/requirements.txt` → o zip já traz o corrigido (adiciona `boto3` e `python-dotenv`).
2. `auth-service/main.go` → **delete a linha** `mux.HandleFunc("/admin/api-keys", app.createKeyHandler)` (rota que cria API keys SEM autenticação — detalhe em `local/auth-service/PATCH-SEGURANCA.md`). O zip também traz o Dockerfile multi-stage do auth (era o único single-stage dos 5).

**Por quê**: a imagem `analytics-service:latest` atual **crasha no boot** (`ModuleNotFoundError: boto3`) — aplicar o manifesto da Etapa 4 sem rebuild = CrashLoopBackOff garantido. E a rota desprotegida do auth vira porta aberta na internet assim que o Ingress da Etapa 5 subir.

**Onde**: terminal, raiz do repo.

```bash
# 1) edite local/auth-service/main.go (delete a linha citada acima), depois:
cd local/analytics-service && docker build -t robertoribeiroo/analytics-service:latest . && docker push robertoribeiroo/analytics-service:latest
cd ../auth-service       && docker build -t robertoribeiroo/auth-service:latest . && docker push robertoribeiroo/auth-service:latest
cd ../..
```

**Validação**: `docker run --rm robertoribeiroo/analytics-service:latest python -c "import boto3; print('boto3 ok')"`.
**Erro comum**: esquecer o push → o EKS continua puxando a imagem antiga quebrada.

---

## Etapa 4 — Namespace + analytics no EKS

**O quê**: aplicar o namespace versionado e o Deployment/Service/ConfigMap do analytics (nunca existiu no cluster).
**Onde**: kubectl.

```bash
kubectl apply -f cloud/techchallenger-k8s/00-namespace.yaml
kubectl apply -f cloud/techchallenger-k8s/analytics-service.yaml
kubectl get pods -n techchallenger -l app=analytics-service -w
```

**Validação**: pod `Running 1/1`; logs mostram `Iniciando o worker SQS...`.
**Erros comuns**: `CrashLoopBackOff` = você pulou a Etapa 3 (imagem antiga sem boto3). `ImagePullBackOff` = push não concluiu.

---

## Etapa 5 — Ingress (completo + correção do existente)

**O quê**: aplicar as rotas novas (auth/flags/rules) **e** o `evaluation-ingress.yaml` corrigido — o original tinha `rewrite-target: /` que reescrevia todo path pra `/` (ou seja, `/evaluate` chegava como `/` → 404 via Load Balancer; os testes anteriores devem ter passado por port-forward, que não usa o Ingress).
**Onde**: kubectl.

```bash
kubectl apply -f cloud/techchallenger-k8s/evaluation-ingress.yaml
kubectl apply -f cloud/techchallenger-k8s/ingress-completo.yaml
kubectl get ingress -n techchallenger
LB=$(kubectl get ingress evaluation-ingress -n techchallenger -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
```

**Validação** (repare: é 401/403 que prova o roteamento, não /health — `/health` dos serviços Python vive na raiz deles e não é exposto sob o prefixo, de propósito):

```bash
curl -i http://$LB/auth/health        # 200 — auth tem rewrite, /health alcançável
curl -i http://$LB/flags              # 401 "Authorization header obrigatório" = roteou certo!
curl -i http://$LB/rules/qualquer     # 401 = roteou certo
curl -i "http://$LB/evaluate"         # resposta do evaluation (400/401 sem params/key = roteou)
```

**Erro comum**: DNS do LB demora alguns minutos na primeira criação.

---

## Etapa 6 — Reaplicar os 4 Deployments endurecidos

**O quê**: Secret + ConfigMap + requests/limits + probes nos 4 serviços já deployados.
**Por quê**: requisitos explícitos do enunciado; hoje nenhum tem.
**Antes de aplicar**: gere uma `SERVICE_API_KEY` nova (a antiga vazou em repo público) e cole no Secret do `evaluation-service.yaml`:

```bash
curl -X POST http://$LB/auth/admin/keys -H "Authorization: Bearer admin-secreto-123" \
  -H "Content-Type: application/json" -d '{"name":"platform-v2"}'
# copie a chave retornada -> cloud/techchallenger-k8s/evaluation-service.yaml (campo SERVICE_API_KEY)
```

```bash
kubectl apply -f cloud/techchallenger-k8s/auth-service.yaml
kubectl apply -f cloud/techchallenger-k8s/flag-service.yaml
kubectl apply -f cloud/techchallenger-k8s/targeting-service.yaml
kubectl apply -f cloud/techchallenger-k8s/evaluation-service.yaml
kubectl get pods -n techchallenger
```

**Validação**: todos `Running 1/1` (probes passando).
**Erro comum**: pod `0/1` por muito tempo → `kubectl describe pod` e confira se a probe `/health` responde (port-forward + curl ajuda a isolar).

---

## Etapa 7 — HPA + Metrics Server

```bash
kubectl get deployment metrics-server -n kube-system || \
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

kubectl apply -f cloud/techchallenger-k8s/hpa-evaluation-service.yaml
kubectl apply -f cloud/techchallenger-k8s/hpa-analytics-service.yaml
kubectl get hpa -n techchallenger
```

**Validação**: em 1-2 min, coluna `TARGETS` mostra `X%/70%` (não `<unknown>`).
**Erro comum**: `<unknown>` persistente = Metrics Server ainda subindo, ou Deployment sem `resources.requests` (os do pacote têm).

---

## Etapa 8 — Limpeza dos manifests órfãos

```bash
bash scripts/limpar-manifests-obsoletos.sh
kubectl get deploy -n techchallenger | grep -E 'postgres|^redis' \
  && kubectl delete deployment,service auth-postgres flags-postgres targeting-postgres redis -n techchallenger --ignore-not-found
```

**Por quê**: libera capacidade do node group pro HPA escalar de verdade na demo.

---

## Etapa 9 — Validação ponta a ponta (é isso que vai pro vídeo)

```bash
# 1. criar API key (rota protegida)
curl -X POST http://$LB/auth/admin/keys -H "Authorization: Bearer admin-secreto-123" \
  -H "Content-Type: application/json" -d '{"name":"demo"}'
# guarde a chave: TM_KEY=tm_key_...

# 2. criar flag
curl -X POST http://$LB/flags -H "Authorization: Bearer $TM_KEY" \
  -H "Content-Type: application/json" -d '{"name":"checkout_v2","is_enabled":true}'

# 3. avaliar (dispara evento -> SQS -> analytics -> DynamoDB)
curl "http://$LB/evaluate?user_id=user-1&flag_name=checkout_v2" -H "Authorization: Bearer $TM_KEY"

# 4. ver o evento persistido
aws dynamodb scan --table-name ToggleMasterAnalytics --region us-east-1
```

**Resultado esperado**: item com `flag_name: checkout_v2` no scan. Se chegou aqui, está pronto pra gravar — roteiro em `docs/06-ROTEIRO-VIDEO.md`.

---

## Validação local (docker compose) — pro bloco 1 do vídeo

```bash
cd local
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_SESSION_TOKEN=...   # do AWS Details do Academy
export AWS_SQS_URL=https://sqs.us-east-1.amazonaws.com/242686594219/techchallenger-evaluation-events
docker compose up -d --build
docker compose ps          # 9 containers Up — é ESTE print que o enunciado pede

# tabela no DynamoDB local (uma vez):
aws dynamodb create-table --endpoint-url http://localhost:8600 \
  --table-name ToggleMasterAnalytics \
  --attribute-definitions AttributeName=event_id,AttributeType=S \
  --key-schema AttributeName=event_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region us-east-1

# fluxo local: mesma sequência da Etapa 9 trocando $LB por localhost:PORTA
# (auth :8001 SEM prefixo /auth — local não tem ingress: curl -X POST localhost:8001/admin/keys ...)
aws dynamodb scan --endpoint-url http://localhost:8600 --table-name ToggleMasterAnalytics --region us-east-1
```
