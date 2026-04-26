# VectorFlow Gateway Dockerfile
FROM golang:1.21-alpine AS builder
WORKDIR /app
RUN apk add --no-cache git ca-certificates
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o gateway ./cmd/gateway

FROM alpine:3.19
RUN apk --no-cache add ca-certificates curl
RUN adduser -D -g '' appuser
WORKDIR /app
COPY --from=builder /app/gateway .
USER appuser
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s CMD curl -f http://localhost:8080/health || exit 1
CMD ["./gateway"]
