FROM debian:trixie

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      live-build debootstrap git ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /build

ENTRYPOINT ["/build/iso/build.sh"]
