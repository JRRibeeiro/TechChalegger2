#!/usr/bin/env bash
# Roda DEPOIS de criar o cluster EKS no Console e conectar o kubectl. Ver 00-CONSOLE-EKS.md.
set -euo pipefail
echo ">>> Metrics Server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

echo ">>> Nginx Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/aws/deploy.yaml

echo ">>> Aguarde o Load Balancer subir (~3 min). Cheque:"
echo "kubectl get svc -n ingress-nginx"
echo "kubectl get deployment metrics-server -n kube-system"
