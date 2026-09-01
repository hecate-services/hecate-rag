#!/usr/bin/env bash
#
# Build the corpus-sync Rust NIF and copy the artefact into priv/lib/.
# Not wired into rebar3's own build (see rebar.config's own note on why
# rustler/rebar3_cargo aren't declared as deps) -- run this manually, or
# from CI, before a release that needs `hecate_rag_corpus_sync_nif`
# actually loadable.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
CRATE="hecate_rag_corpus_sync_nif"

cd "$ROOT/native/$CRATE"
cargo build --release

mkdir -p "$ROOT/priv/lib"
case "$(uname -s)" in
    Linux*)   ext=so ;;
    Darwin*)  ext=dylib ;;
    MINGW*|MSYS*|CYGWIN*) ext=dll ;;
    *) echo "Unsupported platform: $(uname -s)" >&2; exit 1 ;;
esac

src="$ROOT/native/$CRATE/target/release/lib${CRATE}.${ext}"
dst="$ROOT/priv/lib/lib${CRATE}.${ext}"
cp "$src" "$dst"

echo "Built: $dst"
