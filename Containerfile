# PirateSim Development Container
# Fedora-based container with C++/SDL2/OpenGL development toolchain
# Build: podman build -t piratesim-dev .
# Run: podman run -it --rm -v ${PWD}:/workspace piratesim-dev

FROM fedora:40

# Install development tools and libraries
RUN dnf update -y && dnf install -y \
    # Compiler & Build
    gcc \
    g++ \
    clang \
    cmake \
    make \
    ninja-build \
    pkg-config \
    # C++ Libraries
    SDL2-devel \
    SDL2_mixer-devel \
    mesa-libGL-devel \
    glm-devel \
    # Testing
    gtest-devel \
    # Linting/Analysis
    clang-tools-extra \
    cppcheck \
    # Debugging
    gdb \
    lldb \
    valgrind \
    # Utilities
    git \
    vim \
    nano \
    htop \
    curl \
    wget \
    ca-certificates \
    && dnf clean all

# Create non-root user matching host UID/GID (default 1000:1000, overridden at runtime)
ARG USER_UID=1000
ARG USER_GID=1000
ARG USER_NAME=developer

RUN groupadd --gid ${USER_GID} ${USER_NAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} --shell /bin/bash --create-home ${USER_NAME} \
    && echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USER_NAME} \
    && chmod 0440 /etc/sudoers.d/${USER_NAME}

# Set up workspace directory
WORKDIR /workspace
RUN chown ${USER_NAME}:${USER_NAME} /workspace

# Switch to non-root user
USER ${USER_NAME}

# Default entrypoint - drop to shell for interactive development
ENTRYPOINT ["/bin/bash"]