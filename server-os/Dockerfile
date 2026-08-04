FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    live-build \
    xorriso \
    isolinux \
    syslinux-common \
    squashfs-tools \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY docker-entrypoint.sh /usr/local/bin/camonas-build-iso
RUN chmod +x /usr/local/bin/camonas-build-iso

ENTRYPOINT ["/usr/local/bin/camonas-build-iso"]
