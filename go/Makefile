.PHONY: build test lint run clean docker-build

build:
	go build -o bin/gateway ./cmd/gateway

test:
	go test -v -race ./...

lint:
	golangci-lint run ./...

run:
	go run ./cmd/gateway

clean:
	rm -rf bin/

docker-build:
	docker build -t vectorflow-gateway:latest .
