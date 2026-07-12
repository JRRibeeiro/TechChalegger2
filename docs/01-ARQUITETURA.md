# Arquitetura — ToggleMaster Fase 2

> Versão em texto do diagrama mostrado no chat. Confirmado a partir do código
> real (não é suposição de enunciado).

## Visão lógica

```
[ Cliente ]
    |
    v
[ Ingress nginx ] --/auth--> [ auth-service :8001 (Go) ] --> RDS auth_db
    |               --/flags-> [ flag-service :8002 (Py) ] --> RDS flags_db
    |               --/rules-> [ targeting-service :8003 (Py) ] --> RDS targeting_db
    |               --/------> [ evaluation-service :8004 (Go) ]
    |                                |  |  |
    |                                |  |  +--> Redis (ElastiCache) [cache]
    |                                |  +--> chama flag-service e targeting-service
    |                                |       (busca flag + regra pra decidir)
    |                                +--> chama auth-service (valida SERVICE_API_KEY)
    |                                +--> produz evento --> SQS
    |
    +-- (fora do Ingress) SQS --> analytics-service :8005 (Py) --> DynamoDB (ToggleMasterAnalytics)
```

`analytics-service` não fica atrás do Ingress — não há requisito de tráfego
HTTP de entrada pra ele (é um consumidor de fila), só o `/health` interno pra
probe. Essa é uma decisão de design, não uma omissão.

## Grafo de chamadas do evaluation-service (confirmado no código)

`evaluation-service` é o único que fala com todo mundo:
- `AUTH_SERVICE_URL` → valida a `SERVICE_API_KEY` antes de processar
- `FLAG_SERVICE_URL` → busca a definição da flag
- `TARGETING_SERVICE_URL` → busca a regra de segmentação
- Redis → cache (evita bater em flag/targeting-service toda vez)
- SQS → publica `{user_id, flag_name, result, timestamp}` de forma
  fire-and-forget (erro de envio só loga, não derruba a resposta ao cliente —
  boa prática, isolou a falha do SQS do hot path)

## Por que cada peça de dado está onde está

| Decisão | Por quê | Trade-off | Fora do Academy seria |
|---|---|---|---|
| 3 RDS separados (não 1 compartilhado) | Isolamento por serviço — cada um dono do próprio schema, sem acoplamento de banco | 3× custo de instância vs. 1 instância com 3 databases | Aurora Serverless v2 reduziria custo ocioso mantendo o isolamento |
| Redis só no evaluation-service | É o hot path — bater em Postgres a cada avaliação adicionaria latência de rede+query que o resto do sistema não precisa pagar | Cache pode ficar stale se uma flag mudar e ninguém invalidar/expirar | Mesmo padrão, TTL curto já resolve a maior parte |
| DynamoDB no analytics | Escrita em volume alto, consulta simples por chave — não precisa de relacional | Sem joins/queries complexas se um dia precisar analisar dados de forma mais rica | Mesma escolha provavelmente, é o padrão de mercado pra esse tipo de evento |
| SQS entre evaluation e analytics | Desacopla o hot path (sensível a latência) do processamento de analytics (pode atrasar sem problema) | Mais uma peça de infra pra gerenciar | Igual — esse desenho não muda fora do Academy |
| HPA por CPU no analytics-service | Sem IRSA, KEDA não autentica no SQS/CloudWatch pra ler profundidade de fila — CPU é o proxy disponível | É indireto: só escala depois que a CPU já subiu (mensagem chegou, foi processada, CPU subiu), não escala a zero | KEDA com `ScaledObject` monitorando `ApproximateNumberOfMessagesVisible` direto na fila — escala antes da carga virar CPU, inclusive de/para zero |

## Sobre credenciais AWS nos pods (ponto que já te mordeu)

Sem IRSA, os pods não recebem uma identidade própria — eles herdam a
permissão da **LabRole do nó** via Instance Metadata Service (IMDS) do EC2,
*se* o IMDS estiver acessível de dentro do Pod. Na maioria das configurações
padrão isso funciona, mas instâncias criadas com hop-limit de metadata = 1
bloqueiam esse acesso pra containers (é um hardening de segurança comum,
inclusive recomendado pela própria AWS em outros contextos). O sintoma bate
exatamente com o seu `NoCredentialProviders`. Passo a passo de diagnóstico e
correção: `docs/03-RUNBOOK-CREDENCIAIS-SQS.md`.

Limitação real pra citar no relatório: como não há IRSA, **todos os pods do
nó compartilham a mesma permissão ampla da LabRole** — não há isolamento por
serviço (o analytics-service, por exemplo, tecnicamente consegue chamar
qualquer API que a LabRole permita, não só DynamoDB/SQS). Isso é uma
limitação de segurança real do ambiente Academy, não um erro seu.

## Rotas do Ingress — atenção nessa parte

O enunciado usa "/auth", "/flags", "/targeting" como *exemplo* ilustrativo.
No código real, as rotas são:

- `auth-service`: `/validate`, `/admin/keys`, `/admin/api-keys`, `/health` (na raiz)
- `flag-service`: `/flags`, `/flags/<nome>`, `/health`
- `targeting-service`: `/rules`, `/rules/<flag>`, `/health` — **não `/targeting`**
- `evaluation-service`: `/evaluate`, `/health`

Por isso `ingress-completo.yaml` expõe `targeting-service` em `/rules` (bate
1:1 com o código, zero regra de rewrite) em vez de forçar `/targeting` — e
`auth-service` precisa de reescrita de path porque as rotas dele vivem na
raiz, não sob um prefixo `/auth`. Se quiser manter `/targeting` como nome
externo por causa do enunciado, dá pra fazer com rewrite também — mas cada
regra a mais é mais uma coisa que pode quebrar sem necessidade.
