# VectorFlow Worker Dockerfile
FROM rust:alpine AS builder
WORKDIR /app
RUN apk add --no-cache musl-dev
COPY Cargo.toml ./
RUN mkdir src && echo "fn main() {}" > src/main.rs && cargo generate-lockfile && cargo build --release && rm -rf src
COPY src ./src
RUN touch src/main.rs && cargo build --release

FROM alpine:3.19
RUN apk --no-cache add ca-certificates curl
RUN adduser -D -g '' appuser
WORKDIR /app
COPY --from=builder /app/target/release/vectorflow-worker .
USER appuser
EXPOSE 8081
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s CMD curl -f http://localhost:8081/health || exit 1
CMD ["./vectorflow-worker"]
