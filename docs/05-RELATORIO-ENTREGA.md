# O que é o "entregável final", de verdade

Direto do enunciado oficial (páginas 9-10), não do superprompt — vale a
diferença, ver nota no fim. São só **2 peças**:

## 1. Vídeo de demonstração (até 20 min)

É ONDE a explicação técnica acontece — arquitetura, desafios, justificativa
das escolhas de escalabilidade, diferença entre os 3 data stores. Não é o
relatório escrito que carrega isso, é o vídeo. Checklist do que precisa
aparecer (enunciado, literal):

- [ ] `docker compose up` com os 9 containers rodando local
- [ ] Cluster K8s provisionado na nuvem
- [ ] 5 microsserviços como Pods (`kubectl get pods`)
- [ ] Ingress funcionando (curl/Postman na URL do Load Balancer)
- [ ] Carga no evaluation-service + HPA aumentando réplicas (`kubectl get hpa`, `kubectl get pods`)
- [ ] Mensagens manuais na fila SQS
- [ ] HPA do analytics-service reagindo à carga
- [ ] Dados aparecendo no DynamoDB
- [ ] Explicação da arquitetura e dos desafios (ex.: limitações da LabRole)
- [ ] Justificativa da escolha de escalabilidade (HPA por CPU vs. KEDA)
- [ ] Diferença de propósito entre RDS, ElastiCache e DynamoDB

Seu README (seção 8) já tem um roteiro que cobre isso quase 1:1 — quando
você tiver as etapas 1-8 do passo a passo rodando, me chama que eu reviso
esse roteiro com tempo por bloco e ajusto pra ordem de tela.

## 2. Relatório de Entrega (.PDF ou .txt) — este É minimalista

O enunciado pede literalmente isto e nada além:

- Nomes dos participantes, RM e usernames do Discord
- Link dos repositórios
- Link do vídeo salvo no YouTube (ou onde preferir)

Esqueleto pronto pra preencher (falta só os dados do grupo):

```
RELATÓRIO DE ENTREGA — TECH CHALLENGE FASE 2
ToggleMaster — Ecossistema de Microsserviços

Participantes:
- [Nome completo] — RM [xxxxx] — Discord: [usuário]
- (repita por integrante)

Repositório: https://github.com/JRRibeeiro/TechChalegger2
Vídeo: [link do YouTube ou similar]
```

Não precisa de mais nada pra cumprir o requisito. Se quiser, ainda dá pra
anexar o link do badge do Google Cloud Skills Boost pros 10 pontos extras
(seção final do enunciado).

---

## Nota importante: o superprompt pede mais do que o enunciado exige

O documento que você me passou no início (Módulo 6) descreve um relatório
de **16 seções** — contexto, arquitetura, decisões técnicas, limitações,
dificuldades, etc. Isso é bem mais robusto do que o enunciado real pede pro
"Relatório de Entrega". Duas leituras possíveis:

1. **Você só precisa do esqueleto minimalista acima** pra cumprir a entrega
   — a parte de explicação técnica é o vídeo que carrega, não um documento.
2. **Se quiser um relatório mais completo mesmo assim** (documentação pro
   grupo, portfólio, ou se o professor pedir algo além do que está escrito),
   eu já tenho material pronto pra montar isso — arquitetura, trade-offs e
   limitações do Academy já estão escritos em `docs/01-ARQUITETURA.md` e
   `docs/00-DIAGNOSTICO.md`, é só reorganizar no formato de relatório.

Se quiser a versão estendida, me fala que eu monto — só não vou gerar as
16 seções "no escuro" agora porque parte delas (testes e validação,
dificuldades encontradas) só faz sentido escrever depois que você rodar o
passo a passo e souber o que de fato aconteceu.
