# Multi-stage Erlang build for hecate-rag.
# Pushed to ghcr.io/hecate-services/hecate-rag:latest + :semver.

#----------------------------------------------------------------------
# Stage 1 — builder: full Erlang + rebar3 + deps
#----------------------------------------------------------------------
FROM docker.io/erlang:28-alpine AS builder

RUN apk add --no-cache \
    git curl bash \
    build-base cmake \
    perl linux-headers \
    openssl-dev \
    zstd-dev snappy-dev lz4-dev

# Rust via rustup (reckon_db 2.x ships NIFs and hecate_om transitively
# pulls macula_quic, also a Rust NIF; Alpine's rustc is too old for
# their deps).
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain stable --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"
# musl-targeted rustup defaults to crt-static; cdylib NIFs need it off.
ENV RUSTFLAGS="-C target-feature=-crt-static"

WORKDIR /build
COPY rebar.config ./
COPY src ./src
COPY apps ./apps
COPY config ./config

# `_checkouts/` overrides git deps with local source if present (used by
# the dev build, where hecate_embed and hecate_vector have unpublished
# fixes — Ollama backend + dropped `rustler' from applications list).
#
# We copy from `_checkouts_resolved/` (a symlink-free, _build-pruned
# mirror produced by `scripts/sync-checkouts.sh`) because docker/podman
# COPY does not safely follow symlinks. When _checkouts_resolved/ is
# missing or empty, the COPY is a no-op and rebar3 falls back to the
# git deps in the lock file.
COPY _checkouts_resolved ./_checkouts/

# Build Rustler NIFs for the local checkouts (musl-targeted, matches
# the alpine runtime). Skipped silently if a checkout is absent.
RUN set -eu; \
    for dep in hecate_embed hecate_vector; do \
        if [ -d /build/_checkouts/$dep/native ]; then \
            echo "==> building NIF for $dep"; \
            cd /build/_checkouts/$dep && bash scripts/build-nif.sh; \
        fi; \
    done

# Fetch deps + assemble a production release with embedded ERTS.
RUN cd /build && rebar3 as prod tar

#----------------------------------------------------------------------
# Stage 2 — runtime: same Erlang/alpine as builder.
#
# Using a different alpine version risks an OpenSSL ABI mismatch
# (crypto.so was linked against the builder's libcrypto). Pinning to
# the same `erlang:28-alpine' image keeps ABI alignment at the cost
# of a larger image; the dev cycle prizes reliability over thinness.
# Switch to a slimmer base when we have a proper rel-package pipeline.
#----------------------------------------------------------------------
FROM docker.io/erlang:28-alpine

RUN apk add --no-cache libstdc++ ncurses-libs openssl zstd-libs snappy lz4-libs

WORKDIR /app
COPY --from=builder /build/_build/prod/rel/hecate_rag/*.tar.gz /tmp/release.tar.gz
RUN tar xf /tmp/release.tar.gz && rm /tmp/release.tar.gz

# Realm cert mounts here; service socket mounts under /run/macula.
VOLUME ["/etc/hecate/secrets", "/var/lib/hecate-rag"]

EXPOSE 8470

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget --spider -q http://localhost:8470/health || exit 1

ENTRYPOINT ["/app/bin/hecate_rag"]
CMD ["foreground"]
