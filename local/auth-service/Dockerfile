# MULTI-STAGE — o único dos 5 que ainda era single-stage (os outros 4 já
# estavam corretos). Mesmo padrão do evaluation-service. Imagem final cai
# de ~300MB+ (golang:1.22-alpine com toolchain) pra ~15-20MB.
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o auth-service

FROM alpine:3.19
WORKDIR /app
COPY --from=builder /app/auth-service .
EXPOSE 8001
CMD ["./auth-service"]
