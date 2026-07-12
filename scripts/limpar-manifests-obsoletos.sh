#!/usr/bin/env bash
# Estes 5 arquivos são de uma fase anterior do projeto, quando Postgres/Redis
# rodavam DENTRO do cluster (como Pods). Hoje auth/flag/targeting/evaluation-
# service já apontam pros endpoints REAIS de RDS/ElastiCache (confirmado nos
# próprios manifests), então esses arquivos não fazem mais sentido — e pior,
# se alguém rodar "kubectl apply -f cloud/techchallenger-k8s/" (a pasta
# inteira), eles sobem 4 pods extras desnecessários, disputando espaço no
# node group (o mesmo tipo de coisa que já causou o "Too many pods" no seu
# README, seção 1.7).
#
# Rode isso a partir da raiz do repo:
set -e
cd cloud/techchallenger-k8s
mkdir -p _archive
git mv auth-postgres.yaml flags-postgres.yaml targeting-postgres.yaml redis.yaml flags-init-job.yaml _archive/ 2>/dev/null \
  || mv auth-postgres.yaml flags-postgres.yaml targeting-postgres.yaml redis.yaml flags-init-job.yaml _archive/
echo "Arquivos movidos para cloud/techchallenger-k8s/_archive/"
echo ""
echo "Agora confira se algum desses recursos está DE FATO rodando no cluster:"
echo "  kubectl get deploy,svc -n techchallenger | grep -E 'auth-postgres|flags-postgres|targeting-postgres|redis'"
echo ""
echo "Se aparecer algo (e não for o Redis do ElastiCache, claro), apague:"
echo "  kubectl delete deployment,service auth-postgres flags-postgres targeting-postgres redis -n techchallenger --ignore-not-found"
