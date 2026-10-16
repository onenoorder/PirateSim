# PirateSim Container Development Environment

This document describes how to develop PirateSim using the Podman container environment. With this setup, you only need **Podman** installed on your host machine — all C++ build tools, test frameworks, and development utilities run inside the container.

## Quick Start

### Prerequisites
- **Podman** (v4.0+) installed on host
- **podman-compose** (optional, for convenience commands)
- No C++ compiler, CMake, SDL2, or other dev tools needed on host

### Build the Container Image
```bash
# Using Makefile
make container-build

# Or directly with Podman
podman build -t piratesim-dev .
```

### Start Interactive Development Shell
```bash
# Using Makefile (starts container in background, then attaches)
make container-shell

# Or directly with podman-compose
podman-compose up -d dev
podman-compose exec dev bash

# Or directly with Podman (no compose needed)
make podman-shell
# or:
podman run -it --rm \
    -v $(PWD):/workspace:Z \
    -v $(PWD)/dev-env/steamworks-sdk:/opt/steamworks-sdk:Z,ro \
    -w /workspace \
    -e TERM=xterm-256color \
    -e CCACHE_DIR=/workspace/.ccache \
    --user $(id -u):$(id -g) \
    piratesim-dev
```

### Run Tests
```bash
# Using Makefile
make container-test

# Or directly with podman-compose
podman-compose run --rm test

# Or directly with Podman
make podman-test
# or:
podman run --rm \
    -v $(PWD):/workspace:Z \
    -v $(PWD)/dev-env/steamworks-sdk:/opt/steamworks-sdk:Z,ro \
    -w /workspace \
    -e CCACHE_DIR=/workspace/.ccache \
    --user $(id -u):$(id -g) \
    piratesim-dev /workspace/scripts/validate-container.sh
```

### Build Release
```bash
# Using Makefile
make container-release

# Or directly
make podman-release
```

### Clean Up
```bash
make container-clean
```

## Container Details

### Base Image
- **Fedora 40** — provides up-to-date GCC/Clang, CMake, and development libraries
- Native Podman support (Fedora/RHEL ecosystem)

### Installed Tools

| Category | Tools |
|---|---|
| **Compiler & Build** | gcc, g++, clang, cmake, make, ninja-build, pkg-config |
| **C++ Libraries** | SDL2-devel, SDL2_mixer-devel, mesa-libGL-devel, glm-devel |
| **Testing** | gtest-devel (Google Test) |
| **Linting/Analysis** | clang-tools-extra (clang-tidy, clang-format), cppcheck |
| **Debugging** | gdb, lldb, valgrind |
| **Utilities** | git, vim, nano, htop, curl, wget, ca-certificates |

### Non-Root User
The container runs as a non-root user (`developer`) with UID/GID matching your host user (default 1000:1000). This avoids permission issues on volume-mounted files.

The UID/GID are passed at build time via build args:
```bash
podman build --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) -t piratesim-dev .
```

### Source Mounting
- **Development mode:** Volume mount (`-v $(PWD):/workspace:Z`) — edits on host reflect immediately in container
- **CI/Release mode:** `COPY` source into image for reproducible builds

The `:Z` suffix ensures proper SELinux labeling on Fedora/RHEL hosts.

### Steamworks SDK
The Steamworks SDK is not available in package repositories. To use it:

1. Download the Steamworks SDK from the Steamworks developer portal
2. Place it in `./dev-env/steamworks-sdk/` on the host (only the `.gitkeep` placeholder is tracked; SDK contents stay untracked)
3. It will be mounted read-only at `/opt/steamworks-sdk` in the container

```bash
mkdir -p dev-env/steamworks-sdk
# Copy SDK contents here (git-ignored except the .gitkeep placeholder)
```

## IDE Integration

### CMakePresets.json
The project includes `CMakePresets.json` with container-aware presets. To use with VS Code or CLion:

1. Set environment variable `CONTAINER=1` in your IDE's CMake configuration
2. Select the "Container Debug Build" or "Container Release Build" preset
3. The IDE will configure using the container's toolchain

Alternatively, run CMake manually inside the container:
```bash
# Inside container shell
cmake --preset container-debug
cmake --build --preset container-debug
ctest --preset container-debug
```

### clangd / compile_commands.json
The container build generates `compile_commands.json` in the build directory. For IDE integration:
```bash
# Inside container after building
ln -s build/compile_commands.json /workspace/compile_commands.json
```
Then configure clangd to use `/workspace/compile_commands.json`.

## Validation

Run the validation script to verify the container has all required tools:
```bash
make container-test
# or
podman-compose run --rm test
# or directly inside the container:
bash /workspace/scripts/validate-container.sh
```

This checks:
- All required packages installed (compilers, CMake, SDL2, etc.)
- pkg-config can find SDL2, SDL2_mixer, OpenGL, GLM
- Google Test headers and libraries present
- Minimal SDL2+OpenGL+GLM program compiles and runs
- CMake configure/build/test cycle (CMakeLists.txt builds the `piratesim` bootstrap executable and registers gtest/ctest)
- Volume mount permissions (write from container, visible on host)

> Note: always invoke the script through `bash` (as above). The executable bit
> may not survive Windows checkouts.

## Troubleshooting

### Permission Denied on Volume Mount
Ensure the container user matches your host UID/GID:
```bash
# Rebuild with correct UID/GID
podman build --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) -t piratesim-dev .
```

On Windows/macOS with Podman Machine, the UID/GID mapping may differ. Use `podman-compose` which automatically passes `${UID:-1000}` and `${GID:-1000}`.

### SELinux Issues (Fedora/RHEL)
The `:Z` suffix on volume mounts applies the correct SELinux label. If you see permission errors:
```bash
# Relabel the project directory
chcon -Rt container_file_t /path/to/project
```

### Container Won't Start
Check if the image exists:
```bash
podman images piratesim-dev
```

Rebuild if needed:
```bash
make container-build
```

### Steamworks SDK Not Found
Ensure the SDK is in `./dev-env/steamworks-sdk/` on the host. The directory must exist and contain the SDK files for the mount to work.

### Podman Machine (macOS/Windows)
On non-Linux hosts, Podman runs in a VM. Volume mounts work through the VM. Ensure:
- Podman machine is running: `podman machine start`
- Sufficient resources allocated: `podman machine set --cpus 4 --memory 8g`

## CI/CD Integration

The container image can be used in CI pipelines:

```yaml
# Example GitHub Actions step
- name: Build and Test in Container
  run: |
    podman build -t piratesim-dev .
    podman run --rm \
      -v ${{ github.workspace }}:/workspace:Z \
      -w /workspace \
      piratesim-dev bash -c "cmake -B build -DCMAKE_BUILD_TYPE=Debug && cmake --build build --parallel && ctest --test-dir build --output-on-failure"
```

For reproducible CI builds, use the `release` profile or copy source instead of volume mounting:
```dockerfile
# In a CI-specific Containerfile
FROM piratesim-dev AS ci-build
COPY . /workspace
RUN cmake -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build --parallel
```

## Files in This Setup

| File | Purpose |
|---|---|
| `Containerfile` | Main container definition (Dockerfile syntax) |
| `podman-compose.yml` | Orchestration for dev/test/release services |
| `Makefile` | Convenience targets for common operations |
| `scripts/validate-container.sh` | Validation script run inside container |
| `.containerignore` | Exclude patterns for container build context (tracked in git) |
| `CMakeLists.txt` | Minimal CMake skeleton (piratesim target + gtest/ctest wiring) |
| `CMakePresets.json` | IDE integration presets for container/local builds |
| `src/main.cpp` | Bootstrap main() — proof the container toolchain builds project code |
| `tests/container_test.cpp` | gtest smoke test wired into ctest |
| `dev-env/steamworks-sdk/` | Mount point for the Steamworks SDK (contents untracked, `.gitkeep` placeholder tracked) |

## Architecture Notes

- **Single container** — no database, message queue, or external services needed
- **Build/test only** — no X11/Wayland forwarding; the game runs natively on host
- **ccache support** — `CCACHE_DIR=/workspace/.ccache` persists cache across container runs
- **Network isolation** — `network_mode: "none"` available for fully isolated builds (uncomment in compose)

## References

- [Podman Documentation](https://docs.podman.io/)
- [podman-compose](https://github.com/containers/podman-compose)
- [Fedora Package Database](https://packages.fedoraproject.org/)
- [SDL2 Development Libraries](https://wiki.libsdl.org/SDL2/Installation)
- [CMake Presets](https://cmake.org/cmake/help/latest/manual/cmake-presets.7.html)