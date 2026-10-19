#!/bin/bash
# Container validation script
# Runs inside the PirateSim dev container to verify all tools and libraries are present.
#
# Can also be smoke-run on a host without container tooling to verify the script itself
# (counters must reach the summary even when every tool check fails):
#   PIRATESIM_WORKSPACE=. bash scripts/validate-container.sh

set -euo pipefail

# Workspace root: /workspace inside the container; overridable for host smoke runs.
WORKSPACE_DIR="${PIRATESIM_WORKSPACE:-/workspace}"

echo "=== PirateSim Container Validation ==="
echo "Date: $(date)"
echo "User: $(whoami) (UID=$(id -u), GID=$(id -g))"
echo "Workspace: $WORKSPACE_DIR"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass_count=0
fail_count=0

# NOTE: counters MUST use arithmetic assignment (`var=$((var+1))`).
# `((var++))` evaluates to 0 on first use, which under `set -e` terminates the shell.
check() {
    local name="$1"
    local cmd="$2"
    echo -n "Checking $name... "
    if eval "$cmd" >/dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}"
        pass_count=$((pass_count + 1))
    else
        echo -e "${RED}FAIL${NC}"
        fail_count=$((fail_count + 1))
    fi
}

check_output() {
    local name="$1"
    local cmd="$2"
    local output
    echo -n "Checking $name... "
    # The command substitution is part of the if-condition itself so its exit
    # status feeds the branch directly (no `$?` in between, which would break
    # under `set -e` and swallow the status).
    if output=$(eval "$cmd" 2>&1); then
        echo -e "${GREEN}PASS${NC} ($output)"
        pass_count=$((pass_count + 1))
    else
        echo -e "${RED}FAIL${NC} ($output)"
        fail_count=$((fail_count + 1))
    fi
}

# 1. Check required packages are installed
echo "--- Package Checks ---"
check "gcc" "gcc --version"
check "g++" "g++ --version"
check "clang" "clang --version"
check "cmake" "cmake --version"
check "make" "make --version"
check "ninja" "ninja --version"
check "pkg-config" "pkg-config --version"
check "gdb" "gdb --version"
check "lldb" "lldb --version"
check "valgrind" "valgrind --version"
check "cppcheck" "cppcheck --version"
check "clang-tidy" "clang-tidy --version"
check "clang-format" "clang-format --version"
check "git" "git --version"
check "curl" "curl --version"
check "wget" "wget --version"

# 2. Check SDL2 and related libraries via pkg-config
echo ""
echo "--- Library Checks (pkg-config) ---"
check_output "SDL2" "pkg-config --libs --cflags sdl2"
check_output "SDL2_mixer" "pkg-config --libs --cflags SDL2_mixer"
check_output "OpenGL" "pkg-config --libs --cflags gl"
check_output "GLM" "pkg-config --libs --cflags glm 2>/dev/null || echo 'GLM header-only (no pkg-config needed)'"

# 3. Check Google Test
echo ""
echo "--- Test Framework Checks ---"
check "gtest headers" "test -f /usr/include/gtest/gtest.h || test -f /usr/local/include/gtest/gtest.h"
check "gtest libs" "ls /usr/lib64/libgtest*.so 2>/dev/null || ls /usr/lib/libgtest*.so 2>/dev/null || ls /usr/lib/x86_64-linux-gnu/libgtest*.so 2>/dev/null"

# 4. Compile minimal SDL2+OpenGL test program
echo ""
echo "--- Compilation Test ---"
cat > /tmp/test_sdl2_opengl.cpp << 'EOF'
#include <SDL2/SDL.h>
#include <SDL2/SDL_opengl.h>
#include <GL/gl.h>
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <iostream>

int main() {
    // Initialize SDL
    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        std::cerr << "SDL_Init failed: " << SDL_GetError() << std::endl;
        return 1;
    }

    // Create window (hidden, no display needed for compilation test)
    SDL_Window* window = SDL_CreateWindow(
        "Test",
        SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
        640, 480,
        SDL_WINDOW_OPENGL | SDL_WINDOW_HIDDEN
    );
    if (!window) {
        std::cerr << "SDL_CreateWindow failed: " << SDL_GetError() << std::endl;
        SDL_Quit();
        return 1;
    }

    // Create OpenGL context
    SDL_GLContext context = SDL_GL_CreateContext(window);
    if (!context) {
        std::cerr << "SDL_GL_CreateContext failed: " << SDL_GetError() << std::endl;
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 1;
    }

    // Test GLM
    glm::vec3 v(1.0f, 2.0f, 3.0f);
    glm::mat4 m = glm::translate(glm::mat4(1.0f), v);

    // Basic OpenGL call
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    GLenum err = glGetError();
    if (err != GL_NO_ERROR) {
        std::cerr << "OpenGL error: " << err << std::endl;
    }

    // Cleanup
    SDL_GL_DeleteContext(context);
    SDL_DestroyWindow(window);
    SDL_Quit();

    std::cout << "SDL2 + OpenGL + GLM test PASSED (mat4=" << m[0][0] << ")" << std::endl;
    return 0;
}
EOF

check_output "SDL2+OpenGL+GLM compilation" "g++ -std=c++17 /tmp/test_sdl2_opengl.cpp -o /tmp/test_sdl2_opengl \$(pkg-config --cflags --libs sdl2) -lGL 2>&1"

check_output "SDL2+OpenGL+GLM execution" "/tmp/test_sdl2_opengl 2>&1"

# 5. Test CMake configure/build/test cycle
echo ""
echo "--- CMake Build Test ---"
if [ ! -d "$WORKSPACE_DIR" ]; then
    echo "ERROR: workspace directory $WORKSPACE_DIR not found (set PIRATESIM_WORKSPACE to override)." >&2
    exit 1
fi
cd "$WORKSPACE_DIR"

# Check if there's a CMakeLists.txt to test with
if [ -f "CMakeLists.txt" ]; then
    check_output "CMake configure (Debug)" "cmake -B build -DCMAKE_BUILD_TYPE=Debug 2>&1"
    check_output "CMake build" "cmake --build build --parallel 2>&1"

    # Guard against a false PASS: ctest exits 0 even when the suite is empty
    # (e.g. the gtest wiring in CMakeLists.txt failed to register any test).
    # That must count as a failure, not a silent success.
    # (`|| true` is required: grep -c exits 1 on zero matches, which would
    # otherwise terminate the shell under `set -e` — same bug class as D1.)
    registered=$(ctest --test-dir build -N 2>/dev/null | grep -c '^Test #' || true)
    if [ "$registered" -gt 0 ]; then
        echo -n "Checking CMake test registration... "
        echo -e "${GREEN}PASS${NC} ($registered tests registered)"
        pass_count=$((pass_count + 1))
        check_output "CMake test" "ctest --test-dir build --output-on-failure 2>&1"
    else
        echo -n "Checking CMake test registration... "
        echo -e "${RED}FAIL${NC} (ctest reports 0 registered tests - gtest wiring broken?)"
        fail_count=$((fail_count + 1))
    fi
else
    echo -e "${YELLOW}SKIP${NC} - No CMakeLists.txt found in workspace (expected for greenfield project)"
fi

# 6. Volume mount permission test
echo ""
echo "--- Volume Mount Permission Test ---"
test_file="${WORKSPACE_DIR}/.container_write_test_$$"
echo -n "Testing write from container... "
if echo "test" > "$test_file" 2>/dev/null; then
    echo -e "${GREEN}PASS${NC}"
    pass_count=$((pass_count + 1))
    rm -f "$test_file"
else
    echo -e "${RED}FAIL${NC}"
    fail_count=$((fail_count + 1))
fi

# 7. Check Steamworks SDK mount (optional)
echo ""
echo "--- Steamworks SDK Check ---"
if [ -d "/opt/steamworks-sdk" ] && [ "$(ls -A /opt/steamworks-sdk 2>/dev/null)" ]; then
    echo -e "${GREEN}Present${NC} at /opt/steamworks-sdk"
    ls -la /opt/steamworks-sdk/
else
    echo -e "${YELLOW}Not mounted${NC} (optional - place SDK in ./dev-env/steamworks-sdk on host)"
fi

# Summary
echo ""
echo "=== Validation Summary ==="
echo -e "Passed: ${GREEN}$pass_count${NC}"
echo -e "Failed: ${RED}$fail_count${NC}"

if [ "$fail_count" -eq 0 ]; then
    echo -e "${GREEN}All checks passed!${NC}"
    exit 0
else
    echo -e "${RED}Some checks failed.${NC}"
    exit 1
fi
