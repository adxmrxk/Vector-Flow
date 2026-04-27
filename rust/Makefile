.PHONY: build test lint run clean docker-build

build:
	cargo build --release

test:
	cargo test --all

lint:
	cargo clippy -- -D warnings
	cargo fmt --check

run:
	cargo run

clean:
	cargo clean

docker-build:
	docker build -t vectorflow-worker:latest .
