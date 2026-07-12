# Nuvem — ordem de execução

Rode da RAIZ do repo (TechChalegger2). Cada script diz o próximo no fim.

## Ordem
1. `bash cloud/scripts/01-criar-recursos-aws.sh`   → ECR, SQS, DynamoDB. Anote SQS_URL e ECR_REGISTRY.
2. `bash cloud/scripts/02-criar-rds-redis.sh`       → 3 RDS + Redis. Demora ~15 min; siga cheсando status.
3. `bash cloud/scripts/03-build-push-ecr.sh`        → build+push das 5 imagens pro ECR.
4. `bash cloud/scripts/04-ajustar-manifests.sh`     → troca imagem docker.io→ECR nos manifests.
5. **Console: criar cluster EKS** → siga `00-CONSOLE-EKS.md` (parte manual, ~20 min).
6. `bash cloud/scripts/05-configurar-cluster.sh`    → Metrics Server + Nginx Ingress.
7. **Editar Secrets** com endpoints reais do RDS/Redis/SQS (ver abaixo).
8. `bash cloud/scripts/06-deploy-app.sh`            → aplica tudo (deployments, services, ingress, HPA).
9. Validar (Etapa 9 do docs/04-PASSO-A-PASSO.md) e gravar.

## Onde colar os endpoints reais (passo 7)
Depois do 02, pegue os endpoints:
    aws rds describe-db-instances --region us-east-1 \
      --query 'DBInstances[].[DBInstanceIdentifier,Endpoint.Address]' --output table
    aws elasticache describe-cache-clusters --show-cache-node-info --region us-east-1 \
      --query 'CacheClusters[].CacheNodes[].Endpoint.Address' --output text

Edite em cloud/techchallenger-k8s/:
- auth-service.yaml      → Secret DATABASE_URL: host = endpoint do auth-db
- flag-service.yaml      → Secret DATABASE_URL: host = endpoint do flags-db
- targeting-service.yaml → Secret DATABASE_URL: host = endpoint do targeting-db
- evaluation-service.yaml→ Secret REDIS_URL: host = endpoint do Redis; ConfigMap AWS_SQS_URL = SQS_URL
- analytics-service.yaml → ConfigMap AWS_SQS_URL = SQS_URL (DynamoDB e região já ok)

## Popular schema nos RDS (uma vez, após RDS ficar "available")
Os init.sql criam as tabelas. Rode de dentro do cluster ou de uma máquina com acesso:
    psql "postgres://auth_user:auth_pass_123@<endpoint-auth>:5432/auth_db"        -f local/auth-service/db/init.sql
    psql "postgres://flags_user:flags_pass_123@<endpoint-flags>:5432/flags_db"    -f local/flag-service/db/init.sql
    psql "postgres://targeting_user:targeting_password12345@<endpoint-targeting>:5432/targeting_db" -f local/targeting-service/db/init.sql
