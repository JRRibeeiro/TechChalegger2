# Relatório Técnico e README – TechChalegger2 (Fase 2 – Microsserviços no Kubernetes)

> Este documento consolida **tudo o que foi implementado e depurado** no projeto ToggleMaster (Fase 2), cobrindo:
> - **Execução local** (Docker Compose)
> - **Execução em nuvem (AWS Academy / EKS)** com serviços gerenciados (RDS, ElastiCache, SQS e DynamoDB)
> - **Principais problemas reais encontrados** (código, contrato e infraestrutura) e como foram resolvidos
> - **Passo a passo de validação**, retomada do lab e roteiro para o vídeo de entrega

---

## 0. Contexto e objetivo

Na Fase 1 o ToggleMaster era monolítico. Na Fase 2 ele foi dividido em um ecossistema de microsserviços:

- **auth-service (Go)**: emite e valida API Keys (PostgreSQL)
- **flag-service (Python/Flask + Gunicorn)**: CRUD de flags (PostgreSQL)
- **targeting-service (Python/Flask + Gunicorn)**: regras de segmentação (PostgreSQL)
- **evaluation-service (Go)**: hot-path de avaliação, cache em Redis, produz eventos (Redis + SQS)
- **analytics-service (Python)**: consome SQS e grava no DynamoDB (SQS + DynamoDB)

No **AWS Academy** existem limitações de IAM (não é possível criar roles novas livremente), então o desenho foi adaptado usando a **LabRole** e um caminho mais "manual" para permissões e escalabilidade.

**Estado atual: fluxo validado ponta a ponta na nuvem** — curl no Load Balancer → evaluation → auth/flag → Redis → SQS → analytics → item gravado no DynamoDB.

---

## 1. Correções e ajustes necessários (o que realmente quebrou)

Esta seção documenta problemas reais de **código + schema + execução em k8s/cloud** que exigiram correções para o ecossistema funcionar de ponta a ponta.

### 1.1 Validação de API Key – inconsistência entre chave, hash e schema

**Sintomas:**
- `/validate` retornava `Chave de API inválida ou inativa` mesmo quando a chave era recém-criada.
- Logs do `auth-service` mostravam erros de coluna inexistente (`key_hash` ou `is_active`).

**Causa raiz (código x banco):**
- O `auth-service` aplica `SHA-256` na chave recebida e procura no banco por `key_hash`.
- O código fazia query em `is_active`, mas o schema inicial tinha `active`.

**Correção aplicada:**
- Schema final do `auth_db.api_keys` compatível com o código: `key_hash` (hash SHA-256 hex) + `is_active` (BOOLEAN).

### 1.2 `pgcrypto` ausente no Postgres

**Sintoma:** `ERROR: function digest(unknown, unknown) does not exist`

**Correção:** `CREATE EXTENSION IF NOT EXISTS pgcrypto;`

### 1.3 Tabelas inexistentes nos RDS (500 nos serviços)

**Sintoma:** `relation "flags" does not exist` (e equivalentes em auth/targeting).

**Causa raiz:** RDS não executa `db/init.sql` automaticamente.

**Correção aplicada:** schema criado via pod temporário `postgres:15` rodando `psql` direto contra cada RDS (`api_keys`, `flags`, `targeting_rules`).

### 1.4 Chave de "plataforma" vs chave de "serviço" (401 nas chamadas internas)

**Sintoma:** `evaluation-service` retornava `Erro interno ao avaliar a flag`; log: `flag-service retornou status 401`.

**Causa raiz:** o Secret `SERVICE_API_KEY` do evaluation estava com placeholder, não com uma chave real emitida pelo auth.

**Correção aplicada:** chave criada via `/admin/keys` e injetada no Secret:
```bash
kubectl patch secret evaluation-service-secret -n techchallenger --type='json' \
  -p='[{"op":"replace","path":"/data/SERVICE_API_KEY","value":"'$(echo -n "$TM_KEY" | base64 -w0)'"}]'
kubectl rollout restart deployment/evaluation-service -n techchallenger
```

### 1.5 Redis mascarando erros (cache persistia decisões antigas)

**Correção:** limpar cache após alterar flags/regras/chaves: `redis-cli FLUSHALL`.

### 1.6 Security groups bloqueando RDS e Redis (i/o timeout)

**Sintoma:** pods em CrashLoop; log do evaluation: `dial tcp 172.31.x.x:6379: i/o timeout`; auth/flag/targeting sem conseguir conectar no Postgres.

**Causa raiz:** o security group default da VPC não liberava 5432/6379 para o tráfego interno; o ElastiCache usa o mesmo SG (visível apenas pela ENI, não pela API do ElastiCache).

**Correção aplicada:**
```bash
aws ec2 authorize-security-group-ingress --group-id sg-0b86c8bcfb538fb93 --protocol tcp --port 5432 --cidr 172.31.0.0/16 --region us-east-1
aws ec2 authorize-security-group-ingress --group-id sg-0b86c8bcfb538fb93 --protocol tcp --port 6379 --cidr 172.31.0.0/16 --region us-east-1
```

### 1.7 SQS: `NoCredentialProviders` / `Unable to locate credentials` — RESOLVIDO

**Sintoma:** evaluation e analytics não acessavam SQS/DynamoDB de dentro dos pods.

**Causa raiz:** sem IRSA (limitação do Academy), os pods herdam a LabRole via metadata da instância EC2 (IMDS). As instâncias do node group vêm com `http-put-response-hop-limit=1`, que bloqueia containers de alcançar o IMDS.

**Correção aplicada (não cria role nenhuma):**
```bash
for id in $(aws ec2 describe-instances --region us-east-1 --filters "Name=tag:eks:cluster-name,Values=techchallenger" "Name=instance-state-name,Values=running" --query 'Reservations[].Instances[].InstanceId' --output text); do
  aws ec2 modify-instance-metadata-options --instance-id $id --http-put-response-hop-limit 2 --http-endpoint enabled --region us-east-1
done
kubectl rollout restart deployment/analytics-service deployment/evaluation-service -n techchallenger
```
Log de confirmação no analytics: `Found credentials from IAM Role: LabRole`.

Observacao: nos novos criados pelo autoscaling nascem com hop-limit=1; rodar o loop acima novamente quando o node group escalar.

### 1.8 analytics-service crashava no boot (`ModuleNotFoundError: boto3`)

**Causa raiz:** `app.py` importa `boto3` e `dotenv`, mas o `requirements.txt` original não os listava. A imagem buildava e morria no import — motivo real de o serviço nunca ter subido antes.

**Correção:** `boto3` e `python-dotenv` adicionados ao `requirements.txt` + rebuild/push da imagem.

### 1.9 `handlers.go` do auth com linha invalida

**Sintoma:** build da imagem falhava em `go build` com `expected 'package'` na primeira linha do arquivo.

**Correcao:** primeira linha restaurada para `package main`.


### 1.10 Rota de criação de chave sem autenticação no auth-service

**Sintoma:** `main.go` registrava o mesmo handler duas vezes — `/admin/api-keys` sem middleware e `/admin/keys` protegida pela master key. Com o Ingress expondo `/auth`, a rota aberta ficaria pública.

**Correção:** removido o registro desprotegido; criação de chave só via `/admin/keys` com `Authorization: Bearer <MASTER_KEY>`.

### 1.11 Ingress do evaluation com rewrite quebrado

**Sintoma:** via Load Balancer, `/evaluate` retornava 404 (funcionava só por port-forward).

**Causa raiz:** annotation `rewrite-target: /` sem grupo de captura reescreve qualquer path para `/`.

**Correção:** annotation removida; com `path: /` (Prefix) o path original é preservado.

### 1.12 Metrics Server `latest` incompatível

**Sintoma:** `The Deployment "metrics-server" is invalid ... Duplicate value: "https"` no EKS 1.36.

**Correção:** delete da instalação e apply da versão fixa:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.2/components.yaml
```

### 1.13 Ordem de subida no Docker Compose (auth caía no boot)

**Sintoma:** `auth-service` em `Exited (1)` com `connection refused` para o Postgres.

**Correção:** healthcheck (`pg_isready`) nos 3 Postgres e no Redis + `depends_on: condition: service_healthy` nos serviços. Compose sobe os 9 em ordem, sem intervenção.

---

## 2. Arquitetura (local vs cloud)

### 2.1 Visão lógica

```
[ Client ]
   |
   v
[ Ingress nginx / Load Balancer ]
   |-- /auth  -> auth-service:8001  ------> auth_db (RDS)
   |-- /flags -> flag-service:8002  ------> flags_db (RDS)
   |-- /rules -> targeting-service:8003 --> targeting_db (RDS)
   `-- /      -> evaluation-service:8004
                    |-> valida key no auth-service
                    |-> busca flag/regra em flag/targeting
                    |-> Redis (ElastiCache) [cache]
                    `-> SQS (evento)

SQS -> analytics-service:8005 -> DynamoDB (ToggleMasterAnalytics)
```

Observação: o path externo do targeting é `/rules` porque é a rota real do código (`/rules`, `/rules/<flag>`); o `/targeting` do enunciado é exemplo ilustrativo. O `/auth` usa rewrite porque as rotas do auth vivem na raiz.

### 2.2 Local (Docker Compose)

- 9 containers: 5 apps + 3 Postgres + Redis + DynamoDB Local
- Healthchecks controlam a ordem de subida
- SQS não tem emulador local exigido — evaluation/analytics recebem credenciais AWS por variável de ambiente (defaults inofensivos se não exportadas)

### 2.3 Cloud (AWS Academy / EKS)

- Pods stateless no EKS; imagens no **ECR** (5 repositórios)
- Datastores gerenciados: RDS ×3, ElastiCache Redis, SQS, DynamoDB
- Metrics Server + Nginx Ingress Controller (Load Balancer)
- HPA por CPU no evaluation-service (2–6) e analytics-service (1–4)

---

## 3. Execução Local

```bash
cd local
docker compose up -d --build
docker compose ps
```

Criar chave, flag, regra e avaliar (portas 8001–8004, mesmos comandos da seção 5 trocando o host por `localhost:<porta>` — no local o auth atende direto em `localhost:8001/admin/keys`, sem prefixo `/auth`).

Tabela no DynamoDB local (uma vez):
```bash
aws dynamodb create-table --endpoint-url http://localhost:8600 \
  --table-name ToggleMasterAnalytics \
  --attribute-definitions AttributeName=event_id,AttributeType=S \
  --key-schema AttributeName=event_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region us-east-1
```

---

## 4. Execução em Nuvem (AWS Academy / EKS)

### 4.1 Recursos reais (provisionados e validados)

- **Conta:** 007188159471 · Região: us-east-1
- **EKS:** cluster `techchallenger` (Console, Cluster IAM role = LabRole) + node group `t3.medium`, scaling 1/2/4 (Node role = LabRole)
- **ECR:** 007188159471.dkr.ecr.us-east-1.amazonaws.com/{auth,flag,targeting,evaluation,analytics}-service
- **SQS:** https://sqs.us-east-1.amazonaws.com/007188159471/techchallenger-evaluation-events
- **Redis:** techchallenger-redis.pctckz.0001.use1.cache.amazonaws.com:6379
- **RDS auth:** auth-db.cn4pfjmwjrfu.us-east-1.rds.amazonaws.com (auth_user)
- **RDS flags:** flags-db.cn4pfjmwjrfu.us-east-1.rds.amazonaws.com (flags_user)
- **RDS targeting:** targeting-db.cn4pfjmwjrfu.us-east-1.rds.amazonaws.com (targeting_user)
- **DynamoDB:** ToggleMasterAnalytics (PK event_id)

### 4.2 Provisionamento por script (cloud/scripts/)

```bash
bash cloud/scripts/01-criar-recursos-aws.sh      # ECR + SQS + DynamoDB
bash cloud/scripts/02-criar-rds-redis.sh          # 3 RDS + ElastiCache (~15 min)
bash cloud/scripts/03-build-push-ecr.sh           # build + push das 5 imagens
bash cloud/scripts/04-ajustar-manifests.sh        # aponta manifests pro ECR
# Cluster EKS: criado pelo Console (LabRole) — ver cloud/scripts/00-CONSOLE-EKS.md
bash cloud/scripts/05-configurar-cluster.sh       # Metrics Server + Nginx Ingress
bash cloud/scripts/06-deploy-app.sh               # namespace + manifests + HPA
```

Pós-deploy obrigatório (ordem em `cloud/scripts/00-LEIA-ORDEM.md`): liberar 5432/6379 no SG (1.6), criar schema nos RDS (1.3), ajustar hop-limit (1.7) e injetar `SERVICE_API_KEY` real (1.4).

### 4.3 Validação via Load Balancer

```bash
LB=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl -i http://$LB/auth/health

curl -s -X POST http://$LB/auth/admin/keys \
  -H "Authorization: Bearer admin-secreto-123" \
  -H "Content-Type: application/json" -d '{"name":"platform"}'
# exportar TM_KEY com a chave retornada

curl -s -X POST http://$LB/flags \
  -H "Authorization: Bearer $TM_KEY" \
  -H "Content-Type: application/json" -d '{"name":"checkout_v2","is_enabled":true}'

curl -s "http://$LB/evaluate?user_id=user-1&flag_name=checkout_v2" \
  -H "Authorization: Bearer $TM_KEY"

aws dynamodb scan --table-name ToggleMasterAnalytics --region us-east-1 --max-items 5
```

Resultado validado: `{"flag_name":"checkout_v2","user_id":"user-99","result":true}` e o item correspondente gravado no DynamoDB.

---

## 5. Retomando o lab (AWS Academy)

O Learner Lab preserva os recursos entre sessões (dentro do budget); os EC2 do node group param e religam sozinhos. A cada **Start Lab**:

1. Atualizar credenciais: AWS Details → AWS CLI → colar em `~/.aws/credentials` (substituir o bloco `[default]` inteiro).
2. Validar:
```bash
aws sts get-caller-identity
kubectl get nodes                          # aguardar Ready
kubectl get pods -n techchallenger         # aguardar todos 1/1
LB=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -i http://$LB/auth/health             # esperado: 200
```
3. Se evaluation/analytics logarem erro de credencial após o restart dos nós, reaplicar o hop-limit (seção 1.7).
4. A `TM_KEY` persiste (está no RDS e no Secret) — não precisa recriar.

---

## 6. Escalabilidade

- Metrics Server v0.7.2 (versão fixa — ver 1.12)
- HPA por CPU: evaluation-service (min 2 / max 6, alvo 70%) e analytics-service (min 1 / max 4, alvo 70%)
- Justificativa: no Academy, KEDA não funciona (depende de IRSA). Com HPA por CPU, o consumo da fila vira carga de CPU no analytics e o HPA reage — workaround previsto no próprio enunciado.

```bash
kubectl get hpa -n techchallenger
```

---

## 7. Registry de imagens: ECR (atualizado)

Na versão inicial as imagens estavam no Docker Hub (limitações de autenticação esperadas no Academy). Na versão final o projeto **usa o ECR conforme o enunciado**: 5 repositórios, login via `aws ecr get-login-password`, e os Deployments referenciam `007188159471.dkr.ecr.us-east-1.amazonaws.com/<svc>:latest`. A LabRole dos nós cobre o pull sem configuração extra. O Docker Hub (`robertoribeiroo/*`) permanece apenas como espelho histórico.

---

## 8. Roteiro do vídeo

Roteiro completo, com tempos, comandos e falas: **`docs/roteiro-video.md`**.

---

## 9. Estado final

- Local: 9 containers validados, subida ordenada por healthcheck
- Cloud: 5 microsserviços Running no EKS, Ingress com Load Balancer respondendo, HPA ativo lendo métricas
- Fluxo ponta a ponta comprovado: LB → evaluation → auth/flag → Redis → SQS → analytics → DynamoDB
- Pendências: nenhuma técnica; falta gravar o vídeo e preencher o relatório (`docs/relatorio-entrega.txt`)
