#!/usr/bin/env bash
# Troca as referências de imagem Docker Hub -> ECR nos manifests. Rode da raiz do repo.
set -euo pipefail
REGION=us-east-1
ACCOUNT=007188159471
REGISTRY=${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com
for svc in auth-service flag-service targeting-service evaluation-service analytics-service; do
  sed -i "s#docker.io/robertoribeiroo/${svc}:latest#${REGISTRY}/${svc}:latest#g" \
    cloud/techchallenger-k8s/${svc}.yaml
done
echo ">>> Manifests apontando pro ECR: ${REGISTRY}"
grep -h "image:" cloud/techchallenger-k8s/*.yaml
