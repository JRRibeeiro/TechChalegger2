# COMECE AQUI 👇

Você está confuso? Normal — são 20+ arquivos. Mas o uso real é simples:

## Os 3 passos

**1. Extraia este zip na raiz do repo** `TechChalegger2` (paths batem 1:1):
```bash
cd caminho/para/TechChalegger2 && unzip -o togglemaster-fase2-correcoes.zip -d .
```

**2. Abra `docs/04-PASSO-A-PASSO.md` e execute as etapas 0→9 em ordem.**
É O arquivo de instruções. Cada etapa diz o quê, por quê, onde, comando,
validação e erro comum. Tempo estimado: 2-4h na primeira passada.

**3. Grave o vídeo com `docs/06-ROTEIRO-VIDEO.md`** e preencha o relatório
mínimo de `docs/05-RELATORIO-ENTREGA.md`. Entregou.

## Antes de começar, você vai precisar preencher 2 coisas

- **`SERVICE_API_KEY` nova** no `cloud/techchallenger-k8s/evaluation-service.yaml`
  (a antiga vazou; o passo a passo gera a nova na Etapa 6 — só não esqueça de colar).
- **Dados do grupo** (nome/RM/Discord) no relatório, no final.

## Mapa: qual arquivo serve pra quê

| Arquivo | Papel | Quando usar |
|---|---|---|
| `docs/04-PASSO-A-PASSO.md` | **Instruções de execução (o principal)** | Agora |
| `docs/03-RUNBOOK-CREDENCIAIS-SQS.md` | Correção detalhada do bug NoCredentialProviders | Na Etapa 1 |
| `docs/06-ROTEIRO-VIDEO.md` | Roteiro falável com tempos e checkpoints | Ao gravar |
| `docs/05-RELATORIO-ENTREGA.md` | O entregável escrito (esqueleto pronto) | Ao entregar |
| `docs/00-DIAGNOSTICO.md` | O que estava errado/faltando e por quê | Leitura de contexto |
| `docs/01-ARQUITETURA.md` | Arquitetura + trade-offs (base pro Bloco 7 do vídeo) | Antes de gravar |
| `docs/02-PLANO-PRIORIZADO.md` | Visão P0→P3 do que falta | Referência rápida |
| `cloud/techchallenger-k8s/*.yaml` | Manifests prontos (o passo a passo manda aplicar) | Etapas 4-7 |
| `local/docker-compose.yml` | Compose corrigido (9 containers) | Etapa local |
| `local/analytics-service/requirements.txt` | Fix do bug que impedia o analytics de subir | Etapa 3 |
| `local/auth-service/Dockerfile` | Multi-stage do auth (único que faltava) | Etapa 3 |
| `local/auth-service/PATCH-SEGURANCA.md` | Correção da rota sem autenticação | Etapa 3 |
| `scripts/limpar-manifests-obsoletos.sh` | Arquiva manifests órfãos | Etapa 8 |

## Se só puder ler UMA coisa
`docs/04-PASSO-A-PASSO.md`. Todo o resto existe pra apoiar ele.
