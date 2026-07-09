# Multi-stage build for the Flexisip conference server, with EKT plugin.
# Stage 1 builds from upstream source with -DENABLE_EKT_SERVER=ON; stage 2
# is a clean runtime image. Unofficial community build. See NOTICE for
# attribution.

# ---- builder stage --------------------------------------------------------
FROM ubuntu:24.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive

# Build tools + flexisip-conference's dev dependencies.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    build-essential \
    ccache \
    cmake \
    doxygen \
    elfutils \
    git \
    ninja-build \
    pkg-config \
    python3 \
    python3-pystache \
    python3-six \
    yasm \
    wget \
    libssl-dev \
    libhiredis-dev \
    libjansson-dev \
    libjsoncpp-dev \
    libsqlite3-dev \
    libpq-dev \
    libmariadb-dev \
    libmariadb-dev-compat \
    libnghttp2-dev \
    libsnmp-dev \
    libxerces-c-dev \
    libsrtp2-dev \
    libgsm1-dev \
    libopus-dev \
    libmbedtls-dev \
    libspeex-dev \
    libspeexdsp-dev \
    libxml2-dev \
    libvpx-dev \
    libsystemd-dev \
    libboost-dev \
    libboost-system-dev \
    libboost-thread-dev \
    libcpp-jwt-dev \
    nlohmann-json3-dev \
    libsoci-dev \
 && rm -rf /var/lib/apt/lists/*

# Build libnghttp2_asio 1.51.0 from source (not in Ubuntu 24.04 repos).
RUN cd /tmp \
 && wget -q https://github.com/nghttp2/nghttp2/releases/download/v1.51.0/nghttp2-1.51.0.tar.gz \
 && tar -xf nghttp2-1.51.0.tar.gz \
 && cmake -S nghttp2-1.51.0 -B nghttp2-1.51.0/build -GNinja -DENABLE_ASIO_LIB=ON \
 && cmake --build nghttp2-1.51.0/build --target install \
 && rm -rf nghttp2-1.51.0 nghttp2-1.51.0.tar.gz \
 && ldconfig

ARG FLEXISIP_CONFERENCE_VERSION=1.0.0
# Clone the main repo shallow (fast) then do a full recursive submodule
# update.  Retry with full cleanup on failure because gitlab.linphone.org
# is sometimes flaky, and a partial clone leaves submodule trees in a
# state that git cannot recover from without deleting the .git/modules
# subtree.
RUN for i in 1 2 3 4 5; do \
      if git clone --depth 1 --branch "${FLEXISIP_CONFERENCE_VERSION}" \
            https://gitlab.linphone.org/BC/public/flexisip-conference.git /src; then \
        break; \
      fi; \
      echo "git clone failed (attempt $i), retrying in 15s"; \
      sleep 15; \
      rm -rf /src; \
    done
WORKDIR /src
RUN for i in 1 2 3 4 5; do \
      echo "=== Submodule fetch attempt $i ==="; \
      if git submodule update --init --recursive; then \
        uninit=$(git submodule status --recursive 2>/dev/null | grep -c '^-' || true); \
        if [ "$uninit" -eq 0 ]; then \
          echo "All submodules OK"; \
          break; \
        fi; \
        echo "Found $uninit uninitialized submodules (git left empty dirs)"; \
      fi; \
      echo "Cleaning submodule state and retrying..."; \
      rm -rf .git/modules/* 2>/dev/null || true; \
      git submodule foreach --recursive 'rm -rf "$(pwd)"' 2>/dev/null || true; \
      sleep 30; \
    done
RUN cmake -G Ninja -B build \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_INSTALL_PREFIX=/opt/belledonne-communications/flexisip-conference \
        -DENABLE_G729=ON \
        -DENABLE_EKT_SERVER=ON \
 && cmake --build build \
 && cmake --install build \
 && tar -C / -czf /install.tgz opt

# ---- runtime stage --------------------------------------------------------
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="flexisip-conference"
LABEL org.opencontainers.image.description="Conference server (unofficial community build) for TeleCrypt-io, with EKT plugin for E2EE"
LABEL org.opencontainers.image.licenses="AGPL-3.0"
LABEL org.opencontainers.image.source="https://github.com/TeleCrypt-io/flexisip-docker"
LABEL org.opencontainers.image.vendor="TeleCrypt-io"
LABEL org.opencontainers.image.documentation="https://github.com/TeleCrypt-io/flexisip-docker/blob/main/README.md"

# Runtime libraries the conference binary links against. Names use the t64
# ABI where the upstream .deb's Depends declares them. Note: no python3
# packages, no libcpp-jwt (header-only on Ubuntu 24.04).
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libsystemd0 \
    libssl3t64 \
    libboost-system1.83.0 \
    libboost-thread1.83.0 \
    libhiredis1.1.0 \
    libjansson4 \
    libjsoncpp25 \
    libsqlite3-0 \
    libpq5 \
    libmariadb3 \
    libnghttp2-14 \
    libsnmp40t64 \
    libxerces-c3.2t64 \
    libsrtp2-1 \
    libgsm1 \
    libopus0 \
    libspeex1 \
    libspeexdsp1 \
    libxml2 \
    libvpx9 \
 && rm -rf /var/lib/apt/lists/*

# Bring in the built conference server (including the EKT plugin) from the
# builder stage via tar (avoids a buildkit cache-mount conflict on COPY).
COPY --from=builder /install.tgz /tmp/install.tgz
RUN tar -xzf /tmp/install.tgz -C / && rm /tmp/install.tgz

VOLUME ["/etc/opt/belledonne-communications"]
VOLUME ["/var/opt/belledonne-communications"]

COPY docker/conference/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["flexisip-conference", "-c", "/etc/opt/belledonne-communications/flexisip-conference/flexisip-conference.conf"]
