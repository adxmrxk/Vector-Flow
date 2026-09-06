# VectorFlow Worker Dockerfile
FROM rust:alpine AS builder
WORKDIR /app
RUN apk add --no-cache musl-dev perl openssl-dev pkgconfig
# Copy the lockfile so dependency versions are reproducible; without it every
# build re-resolves and can pick up breaking upstream releases.
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs && cargo build --release --locked && rm -rf src
COPY src ./src
RUN touch src/main.rs && cargo build --release --locked

FROM alpine:3.19
RUN apk --no-cache add ca-certificates curl
RUN adduser -D -g '' appuser
WORKDIR /app
COPY --from=builder /app/target/release/vectorflow-worker .
USER appuser
EXPOSE 8081
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s CMD curl -f http://localhost:8081/health || exit 1
CMD ["./vectorflow-worker"]
