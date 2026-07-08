# Unofficial community build of the Flexisip conference server.
# Built from official AGPL-licensed source. See NOTICE for attribution.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# OCI metadata
LABEL org.opencontainers.image.title="flexisip-conference"
LABEL org.opencontainers.image.description="Conference server (unofficial community build) for TeleCrypt-io, with optional EKT plugin for E2EE"
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
      libcpp-jwt0 \
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

# Install the conference .deb packages, including the EKT plugin.
# Expected to be in the build context as dist/bc-flexisip-conference*.deb
COPY dist/bc-flexisip-conference*.deb /tmp/debs/
RUN apt-get update \
 && apt-get install -y --no-install-recommends /tmp/debs/*.deb \
 && rm -rf /tmp/debs /var/lib/apt/lists/*

# Persistent data and config
VOLUME ["/etc/opt/belledonne-communications"]
VOLUME ["/var/opt/belledonne-communications"]

# Conference server listens on the proxy on localhost:6064 by default;
# no external ports need to be exposed in the standard layout.

# Entrypoint handles E2EE opt-in by appending SFU + ZRTP settings to the config
# when ENABLE_EKT_SERVER=true.
COPY docker/conference/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

CMD ["flexisip-conference", "-c", "/etc/opt/belledonne-communications/flexisip-conference/flexisip-conference.conf"]
