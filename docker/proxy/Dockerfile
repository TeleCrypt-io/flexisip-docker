# Unofficial community build of the Flexisip SIP proxy.
# Built from official AGPL-licensed source. See NOTICE for attribution.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# OCI metadata
LABEL org.opencontainers.image.title="flexisip-proxy"
LABEL org.opencontainers.image.description="SIP proxy (unofficial community build) for TeleCrypt-io"
LABEL org.opencontainers.image.licenses="AGPL-3.0"
LABEL org.opencontainers.image.source="https://github.com/TeleCrypt-io/flexisip-docker"
LABEL org.opencontainers.image.vendor="TeleCrypt-io"
LABEL org.opencontainers.image.documentation="https://github.com/TeleCrypt-io/flexisip-docker/blob/main/README.md"

# Install runtime dependencies. These must match the libraries the .deb packages link against.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      libsystemd0 \
      libssl3 \
      libboost-system1.83.0 \
      libboost-thread1.83.0 \
      libhiredis1.1.0 \
      libjansson4 \
      libjsoncpp25 \
      libsqlite3-0 \
      libpq5 \
      libmariadb3 \
      libnghttp2-14 \
      libsnmp40 \
      libxerces-c3.2 \
      libsrtp2-1 \
      libgsm1 \
      libopus0 \
      libmbedtls14 \
      libspeex1 \
      libspeexdsp1 \
      libxml2 \
      libvpx9 \
 && rm -rf /var/lib/apt/lists/*

# Install the proxy .deb package(s) built by the build workflow.
# Expected to be in the build context as dist/bc-flexisip*.deb
COPY dist/bc-flexisip*.deb /tmp/debs/
RUN apt-get update \
 && apt-get install -y --no-install-recommends /tmp/debs/*.deb \
 && rm -rf /tmp/debs /var/lib/apt/lists/*

# Persistent data and config
VOLUME ["/etc/opt/belledonne-communications"]
VOLUME ["/var/opt/belledonne-communications"]

# SIP TLS port
EXPOSE 5061/tcp

# Entrypoint is a simple pass-through; proxy has no E2EE toggle.
COPY docker/proxy/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

CMD ["flexisip", "--server", "proxy"]
