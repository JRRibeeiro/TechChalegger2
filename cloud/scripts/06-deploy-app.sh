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
