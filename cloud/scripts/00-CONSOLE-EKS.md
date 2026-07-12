# Criar o cluster EKS no Console (parte manual — exigida pelo enunciado)

O Academy não deixa criar roles, então o cluster usa a LabRole. Por isso Console, não eksctl.

## Cluster
1. Console AWS → EKS → Add cluster → Create.
2. Name: `techchallenger`. Kubernetes version: a padrão sugerida.
3. Cluster service role: **LabRole**.
4. Deixe o resto no padrão. Networking: VPC default, todas as subnets, cluster endpoint **Public**.
5. Create. Espera ~10 min ficar Active.

## Node group
1. No cluster → Compute → Add node group.
2. Name: `ng-techchallenger`. Node IAM role: **LabRole**.
3. Instance type: `t3.medium`. Scaling: min=1, desired=2, max=4.
4. Create. Espera ~5 min ficar Active.

## Conectar o kubectl
    aws eks update-kubeconfig --name techchallenger --region us-east-1
    kubectl get nodes    # deve listar os nós como Ready

Depois disso, volte pro 05-configurar-cluster.sh.

## Corrigir credenciais SQS nos pods (o bug NoCredentialProviders)
Sem IRSA, os pods herdam a LabRole via metadata da instância. Se o evaluation/analytics
logar NoCredentialProviders, ajuste o hop-limit (não cria role):
    kubectl get nodes -o jsonpath='{.items[*].spec.providerID}'   # pega os i-...
    aws ec2 modify-instance-metadata-options --instance-id i-XXXX --http-put-response-hop-limit 2 --http-endpoint enabled
Detalhe completo em docs/03-RUNBOOK-CREDENCIAIS-SQS.md.
