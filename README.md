# Relatório Técnico e README – TechChalegger2 (Fase 2 – Microsserviços no Kubernetes)

> Este documento consolida **tudo o que foi implementado e depurado** no projeto ToggleMaster (Fase 2), cobrindo:
> - **Execução local** (Docker Compose)
> - **Execução em nuvem (AWS Academy / EKS)** com serviços gerenciados (RDS, ElastiCache, SQS e DynamoDB)
> - **Principais problemas reais encontrados** (código, contrato e infraestrutura) e como foram resolvidos
> - **Passo a passo de validação** e roteiro para o vídeo de entrega

---

## 0. Contexto e objetivo

Na Fase 1 o ToggleMaster era monolítico. Na Fase 2 ele foi dividido em um ecossistema de microsserviços:

- **auth-service (Go)**: emite e valida API Keys (PostgreSQL)
- **flag-service (Python/Flask + Gunicorn)**: CRUD de flags (PostgreSQL)
- **targeting-service (Python/Flask + Gunicorn)**: regras de segmentação (PostgreSQL)
- **evaluation-service (Go)**: hot-path de avaliação, cache em Redis, produz eventos (Redis + SQS)
- **analytics-service (Python)**: consome SQS e grava no DynamoDB (SQS + DynamoDB)

No **AWS Academy** existem limitações de IAM (não é possível criar roles novas livremente), então o desenho foi adaptado usando a **LabRole** e um caminho mais “manual” para permissões e escalabilidade.

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
- Em alguns momentos a tabela foi criada com coluna **errada** (`key` em texto puro) e isso quebrava o contrato de validação.

**Correção aplicada:**
- Schema final do `auth_db.api_keys` ficou **compatível com o código**:
  - `key_hash` (TEXT) – hash SHA-256 (hex)
  - `is_active` (BOOLEAN) – estado da chave (ativo/inativo)

Exemplo de validação (header):
```bash
curl http://localhost:8001/validate \
  -H "Authorization: Bearer tm_key_xxx..."
```

Exemplo de hash (debug):
```bash
echo -n "tm_key_xxx..." | sha256sum
```

---

### 1.2 `pgcrypto` ausente no Postgres (digest não existia)

**Sintoma:**
- No Postgres: `ERROR: function digest(unknown, unknown) does not exist`

**Correção aplicada:**
```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;
```

---

### 1.3 Tabela `flags` inexistente no `flags_db` (flag-service 500)

**Sintoma:**
- `POST /flags` retornava erro 500 com detalhe:
  - `relation "flags" does not exist`

**Causa raiz:**
- Banco foi provisionado (ou subido) sem executar `db/init.sql`.
- Em cloud (RDS), a tabela não aparece “automaticamente”.

**Correção aplicada:**
- Criar tabela `flags` no `flags_db` via psql-client (conexão TLS no RDS).

---

### 1.4 Chave de “plataforma” vs chave de “serviço”

**Sintoma:**
- `evaluation-service` chamava `flag-service` e `targeting-service` e era bloqueado por auth.

**Correção aplicada:**
- Criar chave via `/admin/keys` e configurar `SERVICE_API_KEY` no evaluation-service.

---

### 1.5 Redis mascarando erros (cache persistia decisões antigas)

**Correção aplicada:**
- Limpar cache após alterar flags/regras/chaves:
```bash
redis-cli FLUSHALL
```

---

### 1.6 DNS interno vs RDS: serviço apontando para `flags-postgres`

**Sintoma:**
- `could not translate host name "flags-postgres" to address`

**Correção aplicada:**
- Atualizar `DATABASE_URL` para endpoint real do RDS:
  - `flags-db.cngcg0y0s735.us-east-1.rds.amazonaws.com`

---

### 1.7 Pods Pending (Too many pods) e Node único

**Sintoma:**
- `0/1 nodes are available: 1 Too many pods`

**Correção aplicada:**
- Reduzir réplicas temporariamente e evitar pods de debug long-lived.

---

### 1.8 Exec/port-forward instável (TLS internal error)

**Sintoma:**
- `kubectl exec ... tls: internal error`

**Mitigação aplicada:**
- Usar `psql-client` + conexão direta ao RDS em vez de exec no Postgres pod.

---

### 1.9 SQS: `NoCredentialProviders` no evaluation-service

**Sintoma:**
- `Erro ao enviar mensagem para SQS: NoCredentialProviders`

**Causa raiz:**
- No AWS Academy, IRSA/KEDA/Karpenter não é o caminho padrão (limitações IAM).

**Plano:**
- Documentar a limitação e, quando possível, usar permissão do Node (LabRole) ou IRSA em conta pessoal.

---

## 2. Arquitetura (local vs cloud)

### 2.1 Visão lógica

```
[ Client ]
   |
   v
[ evaluation-service ] ---> Redis
   |        |
   |        +--> SQS (eventos)
   |
   +--> flag-service ---> flags_db (PostgreSQL)
   |
   +--> targeting-service ---> targeting_db (PostgreSQL)

auth-service ---> auth_db (PostgreSQL)
analytics-service ---> DynamoDB (consome SQS)
```

### 2.2 Local (Docker Compose)

- 5 apps + 4 “datastores” locais (2/3 Postgres conforme sua composição, Redis, DynamoDB local)
- Tudo acessível em `localhost`, ideal para debugging.

### 2.3 Cloud (AWS Academy / EKS)

- Pods no EKS: serviços stateless
- Datastores gerenciados:
  - RDS (PostgreSQL) para auth/flags/targeting
  - ElastiCache (Redis) para evaluation-service
  - SQS para eventos
  - DynamoDB para analytics-service

---

## 3. README – Execução Local (comandos)

### 3.1 Subir

```bash
docker compose up -d
docker compose ps
```

### 3.2 Criar chave e validar

```bash
curl -X POST http://localhost:8001/admin/keys \
  -H "Authorization: Bearer admin-secreto-123" \
  -H "Content-Type: application/json" \
  -d '{"name":"platform"}'
```

```bash
curl http://localhost:8001/validate \
  -H "Authorization: Bearer <TM_KEY>"
```

### 3.3 Criar flag

```bash
curl -X POST http://localhost:8002/flags \
  -H "Authorization: Bearer <TM_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"name":"checkout_v2","is_enabled":true}'
```

### 3.4 Criar regra

```bash
curl -X POST http://localhost:8003/rules \
  -H "Authorization: Bearer <TM_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"flag_name":"checkout_v2","rules":{"type":"PERCENTAGE","value":30}}'
```

### 3.5 Avaliar

```bash
curl "http://localhost:8004/evaluate?user_id=user-1&flag_name=checkout_v2" \
  -H "Authorization: Bearer <TM_KEY>"
```

---

## 4. README – Execução em Nuvem (AWS Academy / EKS)

### 4.1 Recursos reais usados

- **SQS**: `https://sqs.us-east-1.amazonaws.com/242686594219/techchallenger-evaluation-events`
- **Redis (ElastiCache)**: `clustercfg.techchallenger-redis.mvwnsq.use1.cache.amazonaws.com:6379`
- **RDS targeting**: `techchallenger-targeting-db.cngcg0y0s735.us-east-1.rds.amazonaws.com`  
  user: `targeting_user` / pass: `targeting_password12345`
- **RDS flags**: `flags-db.cngcg0y0s735.us-east-1.rds.amazonaws.com`
- **RDS auth**: (endpoint do auth-postgres em RDS)

### 4.2 Aplicar manifests

```bash
kubectl create ns techchallenger
kubectl apply -f auth-service.yaml
kubectl apply -f flag-service.yaml
kubectl apply -f targeting-service.yaml
kubectl apply -f evaluation-service.yaml
```

```bash
kubectl get pods -n techchallenger -o wide
kubectl get svc  -n techchallenger
```

### 4.3 Validação por port-forward (CloudShell, um por vez)

```bash
kubectl port-forward -n techchallenger deploy/auth-service 8001:8001
```

Criar key:
```bash
curl -X POST http://localhost:8001/admin/keys \
  -H "Authorization: Bearer admin-secreto-123" \
  -H "Content-Type: application/json" \
  -d '{"name":"platform"}'
```

Validar:
```bash
curl http://localhost:8001/validate \
  -H "Authorization: Bearer <TM_KEY>"
```

Flags:
```bash
kubectl port-forward -n techchallenger deploy/flag-service 8002:8002
curl http://localhost:8002/health
curl http://localhost:8002/flags -H "Authorization: Bearer <TM_KEY>"
```

Targeting:
```bash
kubectl port-forward -n techchallenger deploy/targeting-service 8003:8003
curl http://localhost:8003/health
```

Evaluation:
```bash
kubectl port-forward -n techchallenger deploy/evaluation-service 8004:8004
curl "http://localhost:8004/evaluate?user_id=user-1&flag_name=test_flag" \
  -H "Authorization: Bearer <TM_KEY>"
```

---

## 5. Ingress (requisito do enunciado)

Objetivo: expor rotas externas via Load Balancer, para validar a API da sua máquina.

Checklist:
1) Instalar **ingress-nginx** no cluster
2) Criar `Ingress` com rotas:
   - `/auth` -> auth-service:8001
   - `/flags` -> flag-service:8002
   - `/targeting` -> targeting-service:8003
   - `/evaluate` -> evaluation-service:8004
3) Pegar o hostname do Load Balancer e validar com curl/postman.

---

## 6. Escalabilidade (requisito do enunciado)

### 6.1 Metrics Server

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### 6.2 HPA (mínimo exigido no Academy)

- HPA por CPU para `evaluation-service`
- HPA por CPU para `analytics-service` (workaround do Academy)

---

## 7. DynamoDB + analytics-service (requisito do enunciado)

Tabela esperada:
- Nome: `ToggleMasterAnalytics`
- Partition key: `event_id` (String)

Criar via AWS CLI (quando permitido):
```bash
aws dynamodb create-table \
  --table-name ToggleMasterAnalytics \
  --attribute-definitions AttributeName=event_id,AttributeType=S \
  --key-schema AttributeName=event_id,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1
```

---

## 8. Roteiro do Vídeo (até 20 min)

1) Local: docker compose up + docker compose ps (9 containers)
2) Cloud: cluster EKS + kubectl get nodes
3) Pods: kubectl get pods -n techchallenger
4) Ingress: curl na URL do LB
5) Fluxo:
   - criar key
   - criar flag
   - criar regra
   - avaliar
6) Escala:
   - gerar carga e mostrar HPA escalando
7) SQS + DynamoDB:
   - enviar mensagens
   - mostrar itens no DynamoDB
8) Encerramento: explicar limitações do Academy (LabRole) e decisões técnicas

---

## 9. Estado final

- Local: validado ponta a ponta
- Cloud: serviços principais rodando no EKS com RDS + ElastiCache + SQS configurados
- Pendência mais comum em Academy: credenciais por pod para SQS/DynamoDB (ideal seria IRSA em conta pessoal)

---

Fim do documento.

## Nota sobre Registry de Imagens (ECR vs Docker Hub)

**Importante:** apesar do enunciado recomendar o uso do **AWS ECR**, **neste projeto não foi utilizado ECR**.

**Motivo (AWS Academy / LabRole):**
- O ambiente do **AWS Academy** é segmentado e possui limitações de IAM/roles. Na prática, isso costuma gerar atrito com autenticação do ECR (policies, login, permissões no node role / LabRole, tempo de sessão e credenciais), aumentando o tempo de troubleshooting durante a fase de validação.
- Para garantir previsibilidade e cumprir os prazos de demonstração, optamos por publicar as imagens no **Docker Hub**, mantendo o deploy no EKS e o restante da arquitetura exatamente como solicitado.

**Alternativa adotada (Docker Hub):**
As imagens foram geradas localmente (build) e publicadas no Docker Hub para consumo direto pelos Deployments no Kubernetes.

**Repositórios/Imagens utilizadas (Docker Hub):**
- auth-service: https://hub.docker.com/r/robertoribeiroo/auth-service
- flag-service: https://hub.docker.com/r/robertoribeiroo/flag-service
- targeting-service: https://hub.docker.com/r/robertoribeiroo/targeting-service
- evaluation-service: https://hub.docker.com/r/robertoribeiroo/evaluation-service
- analytics-service: https://hub.docker.com/r/robertoribeiroo/analytics-service

> Tags utilizadas: `latest` (para a demo). 
