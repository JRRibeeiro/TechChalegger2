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
