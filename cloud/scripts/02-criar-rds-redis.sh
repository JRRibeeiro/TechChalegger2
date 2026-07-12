#!/usr/bin/env bash
# 3 instancias RDS PostgreSQL + 1 ElastiCache Redis (~15 min ate ficarem available)
set -euo pipefail
REGION=us-east-1

create_rds () {
  aws rds create-db-instance \
    --db-instance-identifier "$1" \
    --db-instance-class db.t3.micro \
    --engine postgres --engine-version 15 \
    --master-username "$2" --master-user-password "$3" \
    --allocated-storage 20 --db-name "$4" \
    --publicly-accessible --no-multi-az \
    --region $REGION >/dev/null 2>&1 && echo "criando $1" || echo "$1 ja existe"
}

create_rds auth-db      auth_user      auth_pass_123           auth_db
create_rds flags-db     flags_user     flags_pass_123          flags_db
create_rds targeting-db targeting_user targeting_password12345 targeting_db

aws elasticache create-cache-cluster \
  --cache-cluster-id techchallenger-redis \
  --engine redis --cache-node-type cache.t3.micro \
  --num-cache-nodes 1 --region $REGION >/dev/null 2>&1 \
  && echo "criando redis" || echo "redis ja existe"

echo ""
echo "status:"
echo "aws rds describe-db-instances --region $REGION --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceStatus,Endpoint.Address]' --output table"
