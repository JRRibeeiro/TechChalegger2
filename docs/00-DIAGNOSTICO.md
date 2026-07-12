# Diagnóstico técnico — TechChalegger2 (Fase 2) · v2 revisado

> Baseado em leitura do código real do repo (commit `3f839f5`), arquivo por
> arquivo. A v2 corrige 2 erros do meu diagnóstico anterior e adiciona 3 bugs
> encontrados na auditoria de código.

## 1. Estado geral

Projeto bem avançado: 5 serviços com código funcional, local validado, EKS +
RDS×3 + ElastiCache + SQS provisionados, 4/5 serviços deployados. O que falta
está concentrado: o pipeline de analytics nunca rodou ponta a ponta (e agora
sabemos exatamente por quê — ver §3.1), e HPA/Secrets/probes não existiam.

## 2. Gap analysis (v2)

| Requisito | Status | Evidência | Ação | Prioridade |
|---|---|---|---|---|
| Dockerfile ×5 multi-stage | 4/5 já eram ✓ (correção: v1 deste doc dizia que nenhum era — errado) | flag/targeting/evaluation/analytics multi-stage; só auth single-stage | Dockerfile novo do auth incluso no pacote | Baixa |
| docker-compose 9 containers | Corrigido no pacote | analytics estava comentado (motivo real no §3.1); faltava dynamodb-local e passthrough de credenciais | `local/docker-compose.yml` v2 | Alta |
| EKS via Console (Opção A) | **Verificar com Roberto** | Existe `local/eks-cluster.yaml` (eksctl) — não dá pra saber pelo repo o que foi usado de fato | Confirmar; se foi eksctl, decidir entre recriar ou documentar | Alta |
| ECR ×5 | Não cumprido (decisão consciente) | README justifica Docker Hub | Manter+defender ou migrar | Média |
| RDS ×3 / ElastiCache / SQS | Feitos | Endpoints reais nos manifests | — | — |
| DynamoDB `ToggleMasterAnalytics` | **Verificar** | Código espera a tabela; sem evidência de criação | Etapa 2 do passo a passo | Alta |
| Metrics Server | **Verificar** | Não aparece em repo | Etapa 7 | Alta |
| Nginx Ingress Controller | Feito | Ingress existente funciona (LB criado) | — | — |
| Ingress (todas rotas) | Parcial **e o existente tem bug** (§3.3) | Só evaluation exposto, e com rewrite quebrado | `evaluation-ingress.yaml` corrigido + `ingress-completo.yaml` | Alta |
| Namespace como manifesto | **Faltava** | Namespace existe no cluster mas sem YAML versionado | `00-namespace.yaml` novo | Média |
| Deployment/Service ×5 | 4/5 | analytics nunca teve manifesto | `analytics-service.yaml` novo | **Crítica** |
| Secrets / ConfigMaps | Não cumprido | Tudo em `env:` texto puro, incl. API key exposta em repo público | Manifests endurecidos no pacote | **Crítica** |
| Requests/Limits + probes | Não cumprido | Nenhum Deployment tinha; todos os 5 serviços expõem `/health` (confirmado no código) | Inclusos nos manifests | Alta |
| HPA ×2 | Não existia | Nenhum arquivo HPA | 2 arquivos novos | **Crítica** |

## 3. Bugs encontrados na auditoria de código (novos na v2)

### 3.1 analytics-service não sobe: `boto3` ausente do requirements.txt

`app.py` importa `boto3`, `botocore` e `dotenv`; o `requirements.txt` só tem
flask/werkzeug/gunicorn. A imagem **builda normal e crasha no boot** com
`ModuleNotFoundError`. Isso explica o serviço estar comentado no compose e
nunca ter ido pro EKS — não era falta de manifesto, era imagem quebrada.
**Consequência prática**: rebuild + push são pré-requisito do deploy
(Etapa 3 do passo a passo). O requirements corrigido está no pacote.
Fora isso, o código está certo: o worker SQS inicia no import do módulo
(nível de módulo, não no `__main__`), então funciona sob gunicorn.

### 3.2 auth-service: rota de criação de key SEM autenticação

`main.go` registra o mesmo handler duas vezes: `/admin/api-keys` **sem**
middleware e `/admin/keys` **com** `masterKeyAuthMiddleware`. Resultado:
qualquer um cria API key válida via `/admin/api-keys` sem conhecer a master
key — e com o Ingress novo expondo `/auth/...`, isso ficaria público na
internet. Correção de 1 linha (deletar o registro desprotegido) em
`local/auth-service/PATCH-SEGURANCA.md`, com alternativa sem tocar em Go.
Ótimo material de "desafio encontrado" pro vídeo.

### 3.3 evaluation-ingress: `rewrite-target: /` reescreve todo path pra `/`

A annotation sem grupo de captura faz `GET /evaluate` chegar no serviço como
`GET /` → 404 via Load Balancer. Os testes que passaram devem ter sido via
port-forward (não atravessa Ingress). Na v1 deste pacote eu orientei "manter
o evaluation-ingress como está" — **orientação errada, retirada**: o arquivo
corrigido (sem a annotation) está no pacote e convive com o
`ingress-completo.yaml` (nginx roteia pelo prefixo mais específico).

## 4. Chave de API exposta (mantido da v1)

`SERVICE_API_KEY` em texto puro em manifesto de repo público. Rotacionar
(Etapa 6 do passo a passo) e passar a viver em `Secret`. A antiga permanece
no histórico git; dado o prazo, rotacionar + não reusar resolve o risco real.

## 5. Manifests órfãos (mantido da v1)

`auth-postgres.yaml`, `flags-postgres.yaml`, `targeting-postgres.yaml`,
`redis.yaml`, `flags-init-job.yaml` são da fase pré-RDS/ElastiCache. Se
aplicados em lote, sobem 4 pods à toa e comem a capacidade que o HPA precisa
na demo. `scripts/limpar-manifests-obsoletos.sh` arquiva tudo.

## 6. Decisão sobre a base: reaproveitar e corrigir

Inalterado da v1, agora com mais evidência: os problemas são pontuais e
todos têm correção pequena e conhecida (1 requirements, 1 linha de Go,
1 annotation, manifests novos). Refazer seria jogar fora trabalho bom.
