#!/usr/bin/env bash
# Aplica namespace, configmaps, secrets, deployments, services, ingress e HPA.
# ANTES de rodar: edite os Secrets nos manifests com os ENDPOINTS REAIS do RDS/Redis/SQS
# (saída dos scripts 01 e 02). Procure por 'rds.amazonaws.com', 'cache.amazonaws.com', 'sqs'.
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
echo ">>> Aplicado. Acompanhe:"
echo "kubectl get pods -n techchallenger -w"
echo "kubectl get hpa -n techchallenger"
echo "kubectl get ingress -n techchallenger"
