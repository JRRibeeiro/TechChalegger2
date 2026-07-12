#!/usr/bin/env bash
# Cria 3 RDS PostgreSQL + 1 ElastiCache Redis. Demora ~10-15 min (rodam em background na AWS).
# IMPORTANTE: usa o security group default da VPC default e acesso público, pra simplificar
# no ambiente de lab. Ajuste SG/subnets se seu lab exigir.
set -euo pipefail
REGION=us-east-1
PG_VERSION=15
CLASS=db.t3.micro

create_rds () {
  local id=$1 user=$2 pass=$3 db=$4
  echo ">>> RDS $id ..."
  aws rds create-db-instance \
    --db-instance-identifier "$id" \
    --db-instance-class $CLASS \
    --engine postgres --engine-version $PG_VERSION \
    --master-username "$user" --master-user-password "$pass" \
    --allocated-storage 20 --db-name "$db" \
    --publicly-accessible --no-multi-az \
    --region $REGION 2>/dev/null && echo "  criando $id" || echo "  $id já existe / erro (ver acima)"
}

create_rds auth-db      auth_user      auth_pass_123          auth_db
create_rds flags-db     flags_user     flags_pass_123         flags_db
create_rds targeting-db targeting_user targeting_password12345 targeting_db

echo ">>> ElastiCache Redis ..."
aws elasticache create-cache-cluster \
  --cache-cluster-id techchallenger-redis \
  --engine redis --cache-node-type cache.t3.micro \
  --num-cache-nodes 1 --region $REGION 2>/dev/null \
  && echo "  criando redis" || echo "  redis já existe / erro"

echo ""
echo ">>> Aguarde ~10-15 min. Cheque status com:"
echo "aws rds describe-db-instances --region $REGION --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceStatus,Endpoint.Address]' --output table"
echo "aws elasticache describe-cache-clusters --show-cache-node-info --region $REGION --query 'CacheClusters[].[CacheClusterId,CacheClusterStatus]' --output table"
