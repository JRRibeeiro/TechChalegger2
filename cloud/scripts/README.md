# Provisionamento da nuvem

Rodar da raiz do repositorio, na ordem:

```bash
bash cloud/scripts/01-criar-recursos-aws.sh   # ECR, SQS, DynamoDB
bash cloud/scripts/02-criar-rds-redis.sh      # 3 RDS + Redis (~15 min)
bash cloud/scripts/03-build-push-ecr.sh       # build e push das imagens
bash cloud/scripts/04-ajustar-manifests.sh    # manifests -> ECR
# criar o cluster EKS pelo Console (abaixo)
bash cloud/scripts/05-configurar-cluster.sh   # Metrics Server + Ingress Controller
bash cloud/scripts/06-deploy-app.sh           # deploy completo
```

## Cluster EKS (Console)

O Academy nao permite criar roles, entao o cluster e criado pelo Console usando a LabRole:

1. EKS > Add cluster > Create (custom configuration)
2. Name `techchallenger`, Cluster IAM role **LabRole**, VPC default, endpoint Public and private
3. Apos Active: Compute > Add node group `ng-techchallenger`, Node IAM role **LabRole**, `t3.medium`, scaling 1/2/4
4. Conectar: `aws eks update-kubeconfig --name techchallenger --region us-east-1`

## Pos-deploy (obrigatorio na primeira vez)

Detalhes de cada item nas secoes 1.3, 1.4, 1.6 e 1.7 do README raiz:

1. Liberar 5432 e 6379 no security group da VPC (secao 1.6)
2. Criar o schema nos 3 RDS via pod psql (secao 1.3)
3. Ajustar o hop-limit das instancias do node group (secao 1.7)
4. Gerar uma API key e injetar no secret do evaluation-service (secao 1.4)
