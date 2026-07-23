FROM ubuntu:24.04

ARG ODIN_RELEASE=dev-2026-07a

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        ca-certificates \
        clang \
        curl \
        lld \
        llvm \
        mingw-w64 \
        tar \
    && rm -rf /var/lib/apt/lists/*

RUN curl --fail --location --retry 5 --show-error \
        "https://github.com/odin-lang/Odin/releases/download/${ODIN_RELEASE}/odin-linux-amd64-${ODIN_RELEASE}.tar.gz" \
        --output /tmp/odin.tar.gz \
    && mkdir --parents /opt/odin \
    && tar --extract --gzip \
        --file /tmp/odin.tar.gz \
        --strip-components=1 \
        --directory /opt/odin \
    && rm /tmp/odin.tar.gz

ENV ODIN_ROOT=/opt/odin
ENV PATH=/opt/odin:${PATH}

WORKDIR /workspace
