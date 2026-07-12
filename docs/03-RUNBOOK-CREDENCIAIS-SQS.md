# Runbook — destravar o SQS (NoCredentialProviders)

Objetivo: fazer o `evaluation-service` conseguir publicar no SQS de dentro do
EKS, sem criar nenhuma role nova (compatível com Academy).

## 1. Confirmar a causa (2 minutos)

Suba um pod descartável no mesmo namespace/node e teste o IMDS diretamente:

```bash
kubectl run imds-test --rm -it --restart=Never -n techchallenger \
  --image=curlimages/curl -- sh
```

Dentro do pod:

```sh
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
curl -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/
```

**Se retornar `LabRole`** (ou o nome da role): o IMDS está acessível, as
credenciais existem — o problema é outra coisa (menos provável dado o erro
exato, mas confirme permissões da LabRole pra `sqs:SendMessage` nesse caso).

**Se travar/der timeout/vier vazio**: confirmado — é bloqueio de hop-limit.
Vá pro passo 2.

## 2. Corrigir o hop-limit do IMDS (causa mais provável)

Isso NÃO cria role nova — só ajusta uma opção de metadata das instâncias EC2
que já existem no seu node group. Rode do seu terminal (AWS CLI configurado
com as credenciais do Academy) ou do CloudShell:

```bash
# 1. Descobrir os instance-id dos nós do node group
kubectl get nodes -o jsonpath='{.items[*].spec.providerID}' | tr ' ' '\n'
# formato: aws:///us-east-1x/i-0123456789abcdef0 -> pegue só o "i-..."

# 2. Pra CADA instance-id encontrado:
aws ec2 modify-instance-metadata-options \
  --instance-id i-xxxxxxxxxxxxxxxxx \
  --http-put-response-hop-limit 2 \
  --http-endpoint enabled
```

Não precisa reiniciar o pod imediatamente — mas se quiser validar rápido,
force um restart do deployment depois de aplicar em todos os nós:

```bash
kubectl rollout restart deployment/evaluation-service -n techchallenger
```

## 3. Se a LabRole não tiver permissão pra `ec2:ModifyInstanceMetadataOptions`

Fallback garantido (funciona sempre, mas as credenciais do Academy expiram
em algumas horas — perfeito pra gravar o vídeo, chato pra deixar rodando
dias):

1. No AWS Academy, abra "AWS Details" → copie `aws_access_key_id`,
   `aws_secret_access_key` e `aws_session_token`.
2. Adicione essas 3 chaves ao `Secret` de `evaluation-service` (e do
   `analytics-service`, mesmo problema) no manifest anexo:

```yaml
stringData:
  AWS_ACCESS_KEY_ID: "..."
  AWS_SECRET_ACCESS_KEY: "..."
  AWS_SESSION_TOKEN: "..."
```

3. Reaplique e reinicie:

```bash
kubectl apply -f cloud/techchallenger-k8s/evaluation-service.yaml
kubectl rollout restart deployment/evaluation-service -n techchallenger
```

Lembrete: se usar esse caminho, precisa atualizar o Secret de novo sempre
que a sessão do Academy expirar — se a gravação do vídeo for em outro dia da
correção do hop-limit, prefira resolver o hop-limit (passo 2), que é
permanente.

## 4. Validar que funcionou

```bash
kubectl logs -n techchallenger deployment/evaluation-service --tail=50 -f
```

Procure por `Evento de avaliação enviado para SQS` (sucesso) em vez de
`Erro ao enviar mensagem para SQS: NoCredentialProviders`. Gere uma
avaliação pra forçar o envio:

```bash
curl "https://<seu-load-balancer>/evaluate?user_id=user-1&flag_name=checkout_v2" \
  -H "Authorization: Bearer <TM_KEY>"
```

## 5. Rotacionar a SERVICE_API_KEY exposta (enquanto você está aqui)

```bash
curl -X POST http://<seu-load-balancer>/auth/admin/keys \
  -H "Authorization: Bearer admin-secreto-123" \
  -H "Content-Type: application/json" \
  -d '{"name":"platform-v2"}'
```

Cole a chave nova no `Secret` de `evaluation-service.yaml` (campo
`SERVICE_API_KEY`) e reaplique.
