# Plano priorizado — o que falta, em ordem (v2)

[obrigatório] = exigido pelo enunciado · [recomendado] = boa prática · [opcional]

## P0 — bloqueadores
1. [obrigatório] Runbook de credenciais SQS (`docs/03-...`) — sem isso, nada de evento na fila.
2. [obrigatório] Tabela DynamoDB `ToggleMasterAnalytics` confirmada/criada.
3. [obrigatório] **Rebuild + push** de `analytics-service` (requirements corrigido — a imagem atual crasha no boot) e de `auth-service` (patch de segurança + multi-stage). Sem este item, o P1.4 falha em CrashLoopBackOff.

## P1 — requisitos formais faltantes
4. [obrigatório] Aplicar `00-namespace.yaml` + `analytics-service.yaml`.
5. [obrigatório] Aplicar `evaluation-ingress.yaml` **corrigido** (o original quebrava /evaluate via LB) + `ingress-completo.yaml`.
6. [obrigatório] Reaplicar os 4 Deployments endurecidos (Secrets/ConfigMaps/limits/probes) — colar a `SERVICE_API_KEY` rotacionada antes.
7. [obrigatório] Metrics Server confirmado + 2 HPAs aplicados.

## P2 — decisões suas
8. Console vs eksctl na criação do cluster (confirmar o que foi usado; recriar ou documentar).
9. ECR vs Docker Hub (justificativa já escrita; avaliar risco de nota).
10. Rodar limpeza dos manifests órfãos (libera capacidade pro HPA na demo).

## P3 — opcional
11. [recomendado] Patch de segurança do auth já entra no item 3; se optar por NÃO tocar no Go, use a alternativa do PATCH-SEGURANCA.md (não expor /auth no ingress).

## Depois
Etapa 9 do passo a passo validada → gravar com `docs/06-ROTEIRO-VIDEO.md` → preencher `docs/05-RELATORIO-ENTREGA.md` → enviar.
