#!/usr/bin/env bash
set -euo pipefail

if [ ! -d .git ] || [ ! -d cloud/techchallenger-k8s ]; then
  echo "Rode este script da raiz do repositorio TechChalegger2."
  exit 1
fi

echo ">>> removendo arquivos de trabalho e manifests obsoletos..."
git rm -q -f --ignore-unmatch \
  COMECE-AQUI.md \
  scripts/limpar-manifests-obsoletos.sh \
  docs/00-DIAGNOSTICO.md docs/01-ARQUITETURA.md docs/02-PLANO-PRIORIZADO.md \
  docs/03-RUNBOOK-CREDENCIAIS-SQS.md docs/04-PASSO-A-PASSO.md \
  docs/05-RELATORIO-ENTREGA.md docs/06-ROTEIRO-VIDEO.md \
  local/auth-service/PATCH-SEGURANCA.md \
  cloud/techchallenger-k8s/auth-postgres.yaml \
  cloud/techchallenger-k8s/flags-postgres.yaml \
  cloud/techchallenger-k8s/targeting-postgres.yaml \
  cloud/techchallenger-k8s/redis.yaml \
  cloud/techchallenger-k8s/flags-init-job.yaml \
  local/auth-postgres.yaml local/auth-service.yaml local/eks-cluster.yaml \
  local/evaluation-service-svc.yaml local/evaluation-service.yaml \
  local/flag-service.yaml local/flags-postgres.yaml local/redis.yaml \
  local/targeting-postgres.yaml local/targeting-service.yaml \
  local/evaluation-service/evaluation-service \
  cloud/scripts/00-CONSOLE-EKS.md cloud/scripts/00-LEIA-ORDEM.md
git rm -q -rf --ignore-unmatch local/k8s
rmdir scripts 2>/dev/null || true

echo ">>> movendo roteiro e relatorio para docs/..."
mkdir -p docs
git mv -f ROTEIRO-VIDEO.md docs/roteiro-video.md
git mv -f RELATORIO-ENTREGA.txt docs/relatorio-entrega.txt

echo ">>> reescrevendo scripts de provisionamento..."

cat > cloud/scripts/01-criar-recursos-aws.sh << 'SH'
#!/usr/bin/env bash
# ECR (5 repositorios), fila SQS e tabela DynamoDB
set -euo pipefail
REGION=us-east-1
ACCOUNT=007188159471

for svc in auth-service flag-service targeting-service evaluation-service analytics-service; do
  aws ecr create-repository --repository-name "$svc" --region $REGION >/dev/null 2>&1 \
    && echo "ecr criado: $svc" || echo "ecr ja existe: $svc"
done

aws sqs create-queue --queue-name techchallenger-evaluation-events --region $REGION >/dev/null 2>&1 \
  && echo "sqs criada" || echo "sqs ja existe"

aws dynamodb create-table \
  --table-name ToggleMasterAnalytics \
  --attribute-definitions AttributeName=event_id,AttributeType=S \
  --key-schema AttributeName=event_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region $REGION >/dev/null 2>&1 \
  && echo "dynamodb criada" || echo "dynamodb ja existe"

echo ""
echo "SQS_URL=$(aws sqs get-queue-url --queue-name techchallenger-evaluation-events --region $REGION --query QueueUrl --output text)"
echo "ECR_REGISTRY=${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
SH

cat > cloud/scripts/02-criar-rds-redis.sh << 'SH'
#!/usr/bin/env bash
# 3 instancias RDS PostgreSQL + 1 ElastiCache Redis (~15 min ate ficarem available)
set -euo pipefail
REGION=us-east-1

create_rds () {
  aws rds create-db-instance \
    --db-instance-identifier "$1" \
    --db-instance-class db.t3.micro \
    --engine postgres --engine-version 15 \
    --master-username "$2" --master-user-password "$3" \
    --allocated-storage 20 --db-name "$4" \
    --publicly-accessible --no-multi-az \
    --region $REGION >/dev/null 2>&1 && echo "criando $1" || echo "$1 ja existe"
}

create_rds auth-db      auth_user      auth_pass_123           auth_db
create_rds flags-db     flags_user     flags_pass_123          flags_db
create_rds targeting-db targeting_user targeting_password12345 targeting_db

aws elasticache create-cache-cluster \
  --cache-cluster-id techchallenger-redis \
  --engine redis --cache-node-type cache.t3.micro \
  --num-cache-nodes 1 --region $REGION >/dev/null 2>&1 \
  && echo "criando redis" || echo "redis ja existe"

echo ""
echo "status:"
echo "aws rds describe-db-instances --region $REGION --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceStatus,Endpoint.Address]' --output table"
SH

cat > cloud/scripts/03-build-push-ecr.sh << 'SH'
#!/usr/bin/env bash
# build e push das 5 imagens (rodar da raiz do repo)
set -euo pipefail
REGION=us-east-1
REGISTRY=007188159471.dkr.ecr.${REGION}.amazonaws.com

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REGISTRY

for svc in auth-service flag-service targeting-service evaluation-service analytics-service; do
  docker build -t ${REGISTRY}/${svc}:latest ./local/${svc}
  docker push ${REGISTRY}/${svc}:latest
done
SH

cat > cloud/scripts/04-ajustar-manifests.sh << 'SH'
#!/usr/bin/env bash
# aponta os manifests para as imagens do ECR (rodar da raiz do repo)
set -euo pipefail
REGISTRY=007188159471.dkr.ecr.us-east-1.amazonaws.com
for svc in auth-service flag-service targeting-service evaluation-service analytics-service; do
  sed -i "s#docker.io/robertoribeiroo/${svc}:latest#${REGISTRY}/${svc}:latest#g" \
    cloud/techchallenger-k8s/${svc}.yaml
done
grep -h "image:" cloud/techchallenger-k8s/*.yaml
SH

cat > cloud/scripts/05-configurar-cluster.sh << 'SH'
#!/usr/bin/env bash
# Metrics Server (versao fixa, latest quebra no EKS 1.36) + Nginx Ingress Controller
set -euo pipefail
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.2/components.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/aws/deploy.yaml
echo ""
echo "aguarde o load balancer: kubectl get svc -n ingress-nginx"
SH

cat > cloud/scripts/06-deploy-app.sh << 'SH'
#!/usr/bin/env bash
# aplica namespace, servicos, ingress e HPA (rodar da raiz do repo)
set -euo pipefail
K=cloud/techchallenger-k8s
kubectl apply -f $K/00-namespace.yaml
kubectl apply -f $K/auth-service.yaml
kubectl apply -f $K/flag-service.yaml
kubectl apply -f $K/targeting-service.yaml
kubectl apply -f $K/evaluation-service.yaml
kubectl apply -f $K/analytics-service.yaml
kubectl apply -f $K/evaluation-ingress.yaml
kubectl apply -f $K/ingress-completo.yaml
kubectl apply -f $K/hpa-evaluation-service.yaml
kubectl apply -f $K/hpa-analytics-service.yaml
kubectl get pods -n techchallenger
SH

cat > cloud/scripts/README.md << 'MD'
# Provisionamento da nuvem

Rodar da raiz do repositorio, na ordem:

```bash
bash cloud/scripts/01-criar-recursos-aws.sh   # ECR, SQS, DynamoDB
bash cloud/scripts/02-criar-rds-redis.sh      # 3 RDS + Redis (~15 min)
bash cloud/scripts/03-build-push-ecr.sh       # build e push das imagens
bash cloud/scripts/04-ajustar-manifests.sh    # manifests -> ECR
# criar o cluster EKS pelo Console (abaixo)
bash cloud/scripts/05-configurar-cluster.sh   # Metrics Server + Ingress Controller
bash cloud/scripts/06-deploy-app.sh           # deploy completo
```

## Cluster EKS (Console)

O Academy nao permite criar roles, entao o cluster e criado pelo Console usando a LabRole:

1. EKS > Add cluster > Create (custom configuration)
2. Name `techchallenger`, Cluster IAM role **LabRole**, VPC default, endpoint Public and private
3. Apos Active: Compute > Add node group `ng-techchallenger`, Node IAM role **LabRole**, `t3.medium`, scaling 1/2/4
4. Conectar: `aws eks update-kubeconfig --name techchallenger --region us-east-1`

## Pos-deploy (obrigatorio na primeira vez)

Detalhes de cada item nas secoes 1.3, 1.4, 1.6 e 1.7 do README raiz:

1. Liberar 5432 e 6379 no security group da VPC (secao 1.6)
2. Criar o schema nos 3 RDS via pod psql (secao 1.3)
3. Ajustar o hop-limit das instancias do node group (secao 1.7)
4. Gerar uma API key e injetar no secret do evaluation-service (secao 1.4)
MD

chmod +x cloud/scripts/*.sh

echo ">>> ajustando README..."
# secao 1.9 sem mencao a texto de terceiros
python3 - << 'PY'
import re
readme = open('README.md', encoding='utf-8').read()

old_19 = re.search(r'### 1\.9 .*?(?=\n### 1\.10)', readme, re.S)
if old_19:
    novo = """### 1.9 `handlers.go` do auth com linha invalida

**Sintoma:** build da imagem falhava em `go build` com `expected 'package'` na primeira linha do arquivo.

**Correcao:** primeira linha restaurada para `package main`.

"""
    readme = readme.replace(old_19.group(0), novo)

readme = readme.replace('**`ROTEIRO-VIDEO.md`** na raiz do repo', '**`docs/roteiro-video.md`**')
readme = readme.replace('(`RELATORIO-ENTREGA.txt`)', '(`docs/relatorio-entrega.txt`)')
readme = readme.replace('\n> Se o node group escalar (HPA criando nós novos), os nós novos nascem com hop-limit=1 — rodar o loop acima de novo.\n',
                        '\nObservacao: nos novos criados pelo autoscaling nascem com hop-limit=1; rodar o loop acima novamente quando o node group escalar.\n')

open('README.md', 'w', encoding='utf-8').write(readme)
print("README ajustado")
PY

echo ">>> commitando..."
git add -A
git commit -q -m "Organiza o repositorio: remove manifests obsoletos e material de trabalho, move roteiro e relatorio para docs, simplifica scripts"
git push
echo ""
echo "Pronto."
