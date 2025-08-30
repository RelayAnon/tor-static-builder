.PHONY: build clean run shell help

help:
	@echo "Tor Static Builder - Available commands:"
	@echo "  make build  - Build Tor static libraries using Docker"
	@echo "  make clean  - Remove output files and Docker volumes"
	@echo "  make shell  - Start interactive shell in build container"
	@echo "  make run    - Alias for 'build'"

build:
	@echo "Building Tor static libraries..."
	@docker-compose up --build
	@echo "Build complete! Check ./output/ for results"

run: build

shell:
	@echo "Starting interactive shell..."
	@docker-compose run --rm tor-builder /bin/bash

clean:
	@echo "Cleaning output and cache..."
	@rm -rf output/
	@docker-compose down -v
	@echo "Clean complete"

# Quick test to verify output
test-output:
	@if [ -f "output/lib/libtor.a" ]; then \
		echo "✓ libtor.a found"; \
		ls -lh output/lib/*.a; \
	else \
		echo "✗ Build output not found. Run 'make build' first"; \
		exit 1; \
	fi