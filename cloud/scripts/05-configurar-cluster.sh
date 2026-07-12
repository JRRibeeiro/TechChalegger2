#!/usr/bin/env bash
# Metrics Server (versao fixa, latest quebra no EKS 1.36) + Nginx Ingress Controller
set -euo pipefail
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.2/components.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/aws/deploy.yaml
echo ""
echo "aguarde o load balancer: kubectl get svc -n ingress-nginx"
