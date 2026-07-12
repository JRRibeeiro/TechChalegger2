# Patch de segurança — rota de criação de key SEM autenticação

## O problema (confirmado no código, main.go)

O auth-service registra o MESMO handler duas vezes:

```go
mux.HandleFunc("/admin/api-keys", app.createKeyHandler)                                   // linha ~54: SEM middleware!
...
mux.Handle("/admin/keys", app.masterKeyAuthMiddleware(http.HandlerFunc(app.createKeyHandler)))  // linha ~61: protegida ✓
```

Ou seja: `POST /admin/api-keys` cria uma API key **sem exigir a master key**.
Com o Ingress expondo o auth-service em `/auth/...`, qualquer pessoa na
internet consegue `POST /auth/admin/api-keys` e ganhar uma chave válida do
sistema. Isso anula a autenticação inteira.

## A correção (1 linha)

Em `local/auth-service/main.go`, DELETE a linha:

```go
mux.HandleFunc("/admin/api-keys", app.createKeyHandler)
```

(A rota protegida `/admin/keys` já faz exatamente a mesma coisa, com auth.)

Depois: rebuild + push da imagem (etapa 3 do passo a passo) e
`kubectl rollout restart deployment/auth-service -n techchallenger`.

## Alternativa, se não quiser tocar no código Go

Não exponha o auth-service no Ingress (remova o bloco `auth-ingress` do
`ingress-completo.yaml`) e crie as keys via port-forward:

```bash
kubectl port-forward svc/auth-service 8001:8001 -n techchallenger
curl -X POST http://localhost:8001/admin/keys -H "Authorization: Bearer admin-secreto-123" \
  -H "Content-Type: application/json" -d '{"name":"demo"}'
```

O patch de 1 linha é a opção recomendada — e rende um ótimo "desafio
encontrado" pra citar no vídeo.
