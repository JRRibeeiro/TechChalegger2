#!/usr/bin/env bash
# Cria via AWS CLI o que NÃO precisa de Console: ECR (5 repos), SQS, DynamoDB.
# RDS e ElastiCache também dá por CLI, mas ficam no 02 (demoram e é bom acompanhar).
# EKS fica no Console (enunciado exige, por causa da LabRole).
set -euo pipefail
REGION=us-east-1
ACCOUNT=007188159471
echo ">>> ECR: criando 5 repositórios..."
for svc in auth-service flag-service targeting-service evaluation-service analytics-service; do
  aws ecr create-repository --repository-name "$svc" --region $REGION 2>/dev/null \
    && echo "  criado: $svc" || echo "  já existe: $svc"
done

echo ">>> SQS: criando fila standard..."
aws sqs create-queue --queue-name techchallenger-evaluation-events --region $REGION 2>/dev/null \
  && echo "  fila criada" || echo "  fila já existe"

echo ">>> DynamoDB: criando tabela ToggleMasterAnalytics (PK event_id)..."
aws dynamodb create-table \
  --table-name ToggleMasterAnalytics \
  --attribute-definitions AttributeName=event_id,AttributeType=S \
  --key-schema AttributeName=event_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region $REGION 2>/dev/null \
  && echo "  tabela criada" || echo "  tabela já existe"

echo ""
echo ">>> Anote estes valores (usados nos próximos passos):"
echo "SQS_URL=$(aws sqs get-queue-url --queue-name techchallenger-evaluation-events --region $REGION --query QueueUrl --output text 2>/dev/null)"
echo "ECR_REGISTRY=${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
echo ""
echo "OK. Próximo: 02-criar-rds-redis.sh"
