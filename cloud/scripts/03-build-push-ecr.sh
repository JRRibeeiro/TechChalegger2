#!/usr/bin/env bash
# Builda as 5 imagens e sobe pro ECR. Rode da RAIZ do repo (onde está a pasta local/).
set -euo pipefail
REGION=us-east-1
ACCOUNT=007188159471
REGISTRY=${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com

echo ">>> Login no ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REGISTRY

for svc in auth-service flag-service targeting-service evaluation-service analytics-service; do
  echo ">>> $svc: build + push..."
  docker build -t ${REGISTRY}/${svc}:latest ./local/${svc}
  docker push ${REGISTRY}/${svc}:latest
done
echo ">>> Todas as 5 imagens no ECR."
echo ">>> IMPORTANTE: edite os manifests em cloud/techchallenger-k8s/*.yaml trocando"
echo "    'docker.io/robertoribeiroo/<svc>:latest' por '${REGISTRY}/<svc>:latest'"
echo "    (ou rode: 04-ajustar-manifests.sh)"
