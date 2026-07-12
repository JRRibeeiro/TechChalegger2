#!/usr/bin/env bash
# aponta os manifests para as imagens do ECR (rodar da raiz do repo)
set -euo pipefail
REGISTRY=007188159471.dkr.ecr.us-east-1.amazonaws.com
for svc in auth-service flag-service targeting-service evaluation-service analytics-service; do
  sed -i "s#docker.io/robertoribeiroo/${svc}:latest#${REGISTRY}/${svc}:latest#g" \
    cloud/techchallenger-k8s/${svc}.yaml
done
grep -h "image:" cloud/techchallenger-k8s/*.yaml
