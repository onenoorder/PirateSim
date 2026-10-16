# PirateSim Development Container Makefile
# Convenience targets for building and testing inside the Podman container

.PHONY: help container-build container-shell container-test container-lint container-clean container-release

# Default target
help:
	@echo "PirateSim Container Development Commands"
	@echo ""
	@echo "  make container-build   - Build the development container image"
	@echo "  make container-shell   - Start interactive shell in dev container"
	@echo "  make container-test    - Run validation tests in container (one-off)"
	@echo "  make container-lint    - Run linting (cppcheck, clang-tidy) in container"
	@echo "  make container-release - Build release configuration in container"
	@echo "  make container-clean   - Remove container images and build artifacts"
	@echo ""

# Build the container image
container-build:
	podman build -t piratesim-dev .

# Start interactive development shell
container-shell:
	podman-compose up -d dev
	podman-compose exec dev bash

# Run validation tests (one-off container)
container-test:
	podman-compose run --rm test

# Run linting tools (skipped until src/ exists)
container-lint:
	@if [ ! -d "$(PWD)/src" ]; then \
	    echo "container-lint: no src/ directory yet (greenfield) - nothing to lint."; \
	else \
	    podman run --rm \
	        -v $(PWD):/workspace:Z \
	        -w /workspace \
	        piratesim-dev bash -c "find src/ -name '*.cpp' -o -name '*.hpp' | xargs cppcheck --enable=all --std=c++17 --suppress=missingIncludeSystem 2>&1 | head -50"; \
	fi

# Build release configuration
container-release:
	podman-compose run --rm release

# Clean up container images and build artifacts
container-clean:
	podman-compose down --rmi all --volumes 2>/dev/null || true
	podman rmi piratesim-dev:latest 2>/dev/null || true
	rm -rf build/ .ccache/ 2>/dev/null || true

# Alternative: direct podman run commands (without podman-compose)
# These work even if podman-compose is not installed

# Build container image directly
podman-build:
	podman build -t piratesim-dev .

# Run interactive dev container directly
podman-shell:
	podman run -it --rm \
	    -v $(PWD):/workspace:Z \
	    -v $(PWD)/dev-env/steamworks-sdk:/opt/steamworks-sdk:Z,ro \
	    -w /workspace \
	    -e TERM=xterm-256color \
	    -e CCACHE_DIR=/workspace/.ccache \
	    --user $(shell id -u):$(shell id -g) \
	    piratesim-dev

# Run validation directly (bash invocation avoids depending on the +x bit
# surviving Windows checkouts; the container user owns the script)
podman-test:
	podman run --rm \
	    -v $(PWD):/workspace:Z \
	    -v $(PWD)/dev-env/steamworks-sdk:/opt/steamworks-sdk:Z,ro \
	    -w /workspace \
	    -e CCACHE_DIR=/workspace/.ccache \
	    --user $(shell id -u):$(shell id -g) \
	    --entrypoint /bin/bash \
	    piratesim-dev /workspace/scripts/validate-container.sh

# Build release directly
podman-release:
	podman run --rm \
	    -v $(PWD):/workspace:Z \
	    -w /workspace \
	    -e CCACHE_DIR=/workspace/.ccache \
	    --user $(shell id -u):$(shell id -g) \
	    piratesim-dev bash -c "cmake -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build --parallel"

# Show container image info
podman-info:
	podman images piratesim-dev