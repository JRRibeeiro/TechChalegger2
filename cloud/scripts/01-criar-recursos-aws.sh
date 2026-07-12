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
