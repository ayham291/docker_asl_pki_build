# Stage 1: Base
FROM golang:1.23-bookworm AS base

ARG CERT_REPO

# Create working directory
WORKDIR /workspace

# Add SSH keys for cloning private repositories
RUN mkdir -p /root/.ssh && chmod 700 /root/.ssh

# Install build dependencies
RUN --mount=type=cache,target=/var/cache/apt \
  apt-get update && \
  apt-get install -y --no-install-recommends \
  build-essential \
  git \
  ssh \
  libssl-dev && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

# Add GitHub to known_hosts
RUN ssh-keyscan github.com >> /root/.ssh/known_hosts

RUN --mount=type=ssh git clone ${CERT_REPO} /c

# Stage 2: Build
FROM base AS build

ARG REPO_NAME

RUN --mount=type=bind,source=./libs-created/lib,target=/usr/local/lib \
  --mount=type=bind,source=./libs-created/include,target=/usr/local/include \
  --mount=type=bind,source=./libs-created/share,target=/usr/local/share \
  --mount=type=cache,target=/root/.cache/go-build \
  ldconfig && \
  GOPROXY=direct go install ${REPO_NAME}

CMD ["bash"]

# Stage 3: Runtime
FROM debian:bookworm-slim AS runtime

ARG REPO_NAME

ENV APP_NAME=${REPO_NAME##*/}

COPY ./libs-created /usr/local

COPY --from=build /go/bin/${APP_NAME%@*} /usr/local/bin/${APP_NAME%@*}

COPY --from=build /c /c

# Make sure date and time are correct
RUN apt-get update && \
  apt-get install -y --no-install-recommends \
  tzdata && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

# Set timezone
RUN ln -snf /usr/share/zoneinfo/Europe/Berlin /etc/localtime && echo Europe/Berlin > /etc/timezone

# Update library cache
RUN ldconfig

# Expose ports
EXPOSE 8443 8080 8181

CMD ["bash"]

