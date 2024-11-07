# Build stage
FROM debian:bookworm-slim AS build

# Install build dependencies
RUN apt-get update && apt-get install -y \
  cmake \
  ninja-build \
  gcc \
  g++ \
  git \
  openssh-client \
  && rm -rf /var/lib/apt/lists/*

# Setup SSH for built-in forwarding
RUN mkdir -p /root/.ssh && \
  chmod 0700 /root/.ssh && \
  ssh-keyscan github.com > /root/.ssh/known_hosts

# Build stage with SSH mounting
FROM build AS clone

ARG REPO_NAME
ARG REPO_SSH_LOCATION
ARG CMAKE_ARGS
ARG REPO_COMMIT

WORKDIR /opt

# Use --mount=type=ssh for secure SSH key forwarding
RUN --mount=type=ssh git clone ${REPO_SSH_LOCATION}/${REPO_NAME}.git /opt/${REPO_NAME}

# Build the source code
WORKDIR /opt/${REPO_NAME}

# Pin the repository to a specific commit
RUN git checkout ${REPO_COMMIT}

RUN mkdir build

WORKDIR /opt/${REPO_NAME}/build

# Create a minimal runtime stage
FROM debian:bookworm-slim AS runtime

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
  golang \
  && rm -rf /var/lib/apt/lists/*

# Create directory for libraries
RUN mkdir -p /usr/local/lib /usr/local/include

# No COPY commands - volumes will handle library mounting

# Update library cache when libraries are mounted
CMD ldconfig && \
  exec "$@"
