#!/usr/bin/env bash
set -euo pipefail
[ -d .git ] || { echo "rode da raiz do repositorio"; exit 1; }

printf '.DS_Store\nThumbs.db\n*:Zone.Identifier\n.env\n__pycache__/\n*.pyc\n.venv/\nvenv/\n' > .gitignore

sed -i 's#SERVICE_API_KEY: "SUBSTITUA_POR_CHAVE_NOVA_ROTACIONADA"#SERVICE_API_KEY: "tm_key_8582ecdb17fe2ede8097c697436117791342e7abafe76c78dab73c2fb98afe32"#' cloud/techchallenger-k8s/evaluation-service.yaml

python3 << 'PY'
r = open('README.md', encoding='utf-8').read()
r = r.replace("> - **Passo a passo de validação**, retomada do lab e roteiro para o vídeo de entrega",
              "> - **Passo a passo de validação** e retomada do lab")
r = r.replace("""## 8. Roteiro do vídeo

Roteiro completo, com tempos, comandos e falas: **`docs/roteiro-video.md`**.

---

## 9. Estado final""", "## 8. Estado final")
r = r.replace("- Pendências: nenhuma técnica; falta gravar o vídeo e preencher o relatório (`docs/relatorio-entrega.txt`)\n", "")
r = r.replace("- 9 containers: 5 apps + 3 Postgres + Redis + DynamoDB Local",
              "- 10 containers: 5 apps + 3 Postgres + Redis + DynamoDB Local (o enunciado cita 2 Postgres; aqui são 3 para espelhar os 3 RDS da nuvem, um banco por serviço)")
r = r.replace("- Local: 9 containers validados, subida ordenada por healthcheck",
              "- Local: 10 containers validados, subida ordenada por healthcheck")
open('README.md','w',encoding='utf-8').write(r)
print("README ok")
PY

cat > docs/roteiro-video.md << 'ROTEIRO_EOF'
# Roteiro de gravação — Fase 2 (15 a 18 min)

Formato: cada cena tem **Executar** (comandos na ordem), **Falar** (fala natural, adapta com suas palavras) e **Por quê** (o que essa cena prova pro avaliador). Os itens do enunciado estão marcados com [E].

---

## Antes de apertar REC

Terminal WSL, dois abertos lado a lado. Console AWS logado com abas em: EKS, RDS, ElastiCache, SQS, DynamoDB.

**Executar (preparação, fora da gravação):**
```bash
# credenciais novas do lab em ~/.aws/credentials (AWS Details > AWS CLI)
aws sts get-caller-identity
kubectl get nodes                          # esperar os 2 Ready
kubectl get pods -n techchallenger         # esperar todos 1/1

LB=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
SQS_URL=https://sqs.us-east-1.amazonaws.com/007188159471/techchallenger-evaluation-events
curl -s http://$LB/auth/health             # esperado: {"status":"ok"}
```

Se evaluation ou analytics estiverem reiniciando com erro de credencial (os nós religam com hop-limit=1), rodar:
```bash
for id in $(aws ec2 describe-instances --region us-east-1 --filters "Name=tag:eks:cluster-name,Values=techchallenger" "Name=instance-state-name,Values=running" --query 'Reservations[].Instances[].InstanceId' --output text); do
  aws ec2 modify-instance-metadata-options --instance-id $id --http-put-response-hop-limit 2 --http-endpoint enabled --region us-east-1
done
kubectl rollout restart deployment/analytics-service deployment/evaluation-service -n techchallenger
```

Só começa a gravar com o `curl /auth/health` respondendo 200.

---

## Cena 1 — Abertura (30s)

**Executar:** nada — tela no diagrama de arquitetura ou no README do repo.

**Falar:** "Tech Challenge Fase 2. Peguei o ToggleMaster, que na Fase 1 era um monolito, e quebrei em cinco microsserviços: auth pra chaves de API, flag pro CRUD de flags, targeting pras regras de segmentação, evaluation que é o caminho quente de decisão, e analytics que consome eventos. Cada um com seu banco: os três primeiros em PostgreSQL, o evaluation com cache em Redis, e o analytics gravando em DynamoDB a partir de uma fila SQS. Vou mostrar isso rodando local em Docker e depois na AWS em Kubernetes."

**Por quê:** o enunciado pede explicação da arquitetura [E]. Abrir com ela dá contexto pra tudo que vem depois e já cumpre parte do requisito.

---

## Cena 2 — Local: Docker Compose (2 min)

**Executar:**
```bash
cd local
docker compose up -d
docker compose ps
```

**Falar:** enquanto sobe — "Cada serviço tem um Dockerfile multi-stage, então a imagem final vai só com o binário ou o runtime, sem toolchain. O compose sobe o ecossistema inteiro: os cinco serviços, três Postgres, um Redis e um DynamoDB local — dez containers no total; o enunciado cita dois Postgres, eu uso três pra espelhar os três RDS da nuvem, um banco por serviço." Quando o `ps` listar: "Aqui os dez de pé. Os bancos têm healthcheck, então os serviços só sobem quando o banco deles já aceita conexão — isso resolve corrida de inicialização."

**Por quê:** requisito literal do vídeo: compose com 9 containers rodando [E]. O comentário do healthcheck mostra decisão técnica sua, não só comando decorado.

---

## Cena 3 — Infra na AWS (2 min)

**Executar:** nada de terminal — passeio pelo Console, uma aba por vez, sem demorar em nenhuma:
1. EKS → cluster `techchallenger` (mostrar Status Active e a Cluster IAM role LabRole) → aba Compute (node group, t3.medium, scaling 1/2/4)
2. RDS → as três instâncias
3. ElastiCache → techchallenger-redis
4. SQS → a fila
5. DynamoDB → tabela ToggleMasterAnalytics

**Falar:** "Cluster EKS criado pelo Console porque no Academy não dá pra criar role — tudo roda com a LabRole, tanto o cluster quanto os nós. Node group com duas máquinas t3.medium, escalando de uma a quatro. Bancos gerenciados: três RDS Postgres separados, um por serviço, um Redis no ElastiCache, a fila SQS e a tabela do DynamoDB. As imagens estão no ECR, um repositório por serviço."

**Por quê:** requisito: mostrar cluster provisionado na nuvem [E]. Citar a LabRole aqui planta a semente da explicação de limitações que fecha o vídeo.

---

## Cena 4 — Pods e Ingress (2 min)

**Executar:**
```bash
kubectl get nodes
kubectl get pods -n techchallenger
kubectl get ingress -n techchallenger
curl -i http://$LB/auth/health
```

**Falar:** "Dois nós prontos, e os cinco microsserviços rodando como pods — o evaluation com duas réplicas porque é o caminho quente. Cada deployment tem requests e limits, probes de readiness e liveness, e a configuração vem de ConfigMaps e Secrets, nada de senha solta no manifest. O acesso externo é pelo Nginx Ingress Controller, que criou esse Load Balancer na AWS. As rotas: /auth cai no auth-service com rewrite, /flags e /rules vão direto, e a raiz cai no evaluation. O curl aqui é da minha máquina pro Load Balancer — 200."

**Por quê:** dois requisitos de uma vez: pods dos 5 serviços [E] e Ingress funcionando com chamada externa [E]. Citar probes/limits/secrets cobre as boas práticas que o enunciado lista.

---

## Cena 5 — Fluxo completo da aplicação (3 min)

**Executar:**
```bash
curl -s -X POST http://$LB/auth/admin/keys -H "Authorization: Bearer admin-secreto-123" -H "Content-Type: application/json" -d '{"name":"video"}'
```
Copiar a chave retornada e exportar:
```bash
TM_KEY=tm_key_...
curl -s -X POST http://$LB/flags -H "Authorization: Bearer $TM_KEY" -H "Content-Type: application/json" -d '{"name":"demo_video","is_enabled":true}'
curl -s "http://$LB/evaluate?user_id=user-1&flag_name=demo_video" -H "Authorization: Bearer $TM_KEY"
```

**Falar:** "Primeiro crio uma chave de API no auth usando a master key. Com ela, crio uma flag no flag-service — foi pro Postgres. Agora a avaliação: o evaluation valida a chave no auth, busca a flag, guarda no Redis pra próxima consulta ser cache hit, responde true pro cliente e, em paralelo, publica o evento de avaliação na fila SQS. Esse evento a gente vai ver chegando no DynamoDB daqui a pouco."

**Por quê:** prova que os serviços conversam entre si de verdade (auth entre serviços, banco, cache) — é o que diferencia "pods de pé" de "sistema funcionando". E arma a cena 7.

---

## Cena 6 — HPA do evaluation sob carga (3 min)

**Executar:** no terminal 2:
```bash
watch -n 2 "kubectl get hpa -n techchallenger; echo; kubectl get pods -n techchallenger -l app=evaluation-service"
```
No terminal 1, gerar carga:
```bash
for i in $(seq 1 8); do ( while true; do curl -s "http://$LB/evaluate?user_id=load$i&flag_name=demo_video" -H "Authorization: Bearer $TM_KEY" >/dev/null; done ) & done
```
Esperar o TARGETS passar de 70% e as réplicas subirem (2 → 3 → 4...). Depois parar:
```bash
kill $(jobs -p)
```

**Falar:** "Oito loops de curl batendo no evaluate. O Metrics Server coleta o consumo, e o HPA está configurado com alvo de 70% de CPU, mínimo duas réplicas, máximo seis. A CPU passou do alvo... e ali o HPA já subiu réplicas novas — dá pra ver os pods novos entrando. Quando a carga parar, ele desescala sozinho depois do período de estabilização."

**Por quê:** requisito literal: gerar carga e mostrar o HPA aumentando réplicas [E]. O watch lado a lado com a carga é a evidência visual mais forte do vídeo.

---

## Cena 7 — SQS, analytics e DynamoDB (3 min)

**Executar:** no terminal 2, trocar o watch:
```bash
watch -n 2 "kubectl get hpa analytics-service-hpa -n techchallenger; echo; kubectl get pods -n techchallenger -l app=analytics-service"
```
No terminal 1, mandar mensagens manuais pra fila:
```bash
for i in $(seq 1 100); do aws sqs send-message --queue-url $SQS_URL --message-body "{\"user_id\":\"u$i\",\"flag_name\":\"demo_video\",\"result\":true,\"timestamp\":\"2026-07-12T12:00:00Z\"}" >/dev/null & done; wait
kubectl logs -n techchallenger deployment/analytics-service --tail=10
aws dynamodb scan --table-name ToggleMasterAnalytics --region us-east-1 --max-items 5
```
Opcional: abrir a tabela no Console e mostrar os itens.

**Falar:** "Cem mensagens direto na fila, simulando pico de eventos. O analytics consome em lote de dez com long polling — o log mostra ele processando e gravando. Isso vira CPU, e o HPA dele reage do mesmo jeito. E aqui no scan do DynamoDB: os eventos gravados, com event_id, usuário, flag e resultado. Repara que também tem o evento da avaliação que fiz na cena anterior — o fluxo evaluation → SQS → analytics → DynamoDB fechou ponta a ponta."

**Por quê:** quatro requisitos numa cena: mensagens manuais no SQS [E], HPA do analytics detectando carga [E], dados no DynamoDB [E], e a prova do pipeline assíncrono completo.

---

## Cena 8 — Fechamento: decisões e limitações (2 a 3 min)

**Executar:** nada — voltar pro diagrama ou pro Console.

**Falar (três blocos, todos cobrados no enunciado):**

Limitações do Academy e desafios [E]: "Sem poder criar roles, tudo herda a LabRole — e os pods pegam essa permissão pelo metadata da instância EC2. O maior problema real do projeto foi esse: as instâncias vêm com hop-limit 1 no metadata, que bloqueia container de pegar credencial, e o SQS falhava com erro de credencial. A correção foi subir o hop-limit pra 2 nas instâncias do node group. Também precisei liberar as portas do Postgres e do Redis no security group da VPC, corrigir uma dependência que faltava no analytics e fechar uma rota do auth que criava chave sem autenticação."

Escalabilidade — por que HPA por CPU e não KEDA [E]: "O jeito ideal de escalar o analytics seria KEDA olhando a profundidade da fila, inclusive escalando de zero. Só que KEDA depende de IRSA, que exige criar role — bloqueado no Academy. O workaround é o HPA por CPU: fila enche, o worker processa mais, CPU sobe, HPA escala. Menos direto, mas funciona e é o caminho que o próprio enunciado prevê pra esse ambiente."

Os três data stores [E]: "RDS pro que é relacional e transacional — chaves, flags e regras, dados que precisam de consistência. ElastiCache Redis como cache de milissegundos no caminho quente da avaliação, pra não bater no Postgres a cada request. E DynamoDB pro analytics: escrita de evento em volume alto, consulta simples por chave, sem precisar de join. Cada armazenamento no papel em que ele é melhor."

Encerrar: "Código, manifests e scripts de provisionamento estão no repositório; o link está no relatório de entrega junto com este vídeo. Valeu."

**Por quê:** são os três itens de explicação obrigatória do enunciado [E][E][E]. Contar os problemas reais (hop-limit, security group) com a solução dada vale mais que um fechamento genérico — mostra que você operou o ambiente de verdade.

---

## Checklist antes de subir o vídeo

- [ ] compose completo, 10 containers (cena 2)
- [ ] cluster no Console (cena 3)
- [ ] 5 microsserviços em pods (cena 4)
- [ ] curl externo no Load Balancer (cena 4)
- [ ] carga + HPA do evaluation escalando (cena 6)
- [ ] mensagens manuais no SQS (cena 7)
- [ ] HPA do analytics reagindo (cena 7)
- [ ] itens no DynamoDB (cena 7)
- [ ] arquitetura e desafios/LabRole explicados (cenas 1 e 8)
- [ ] justificativa HPA por CPU vs KEDA (cena 8)
- [ ] RDS vs ElastiCache vs DynamoDB (cena 8)
ROTEIRO_EOF

git add -A
git commit -m "Ajustes finais: gitignore, chave do evaluation fixada, contagem de containers e roteiro de gravacao"
git push
