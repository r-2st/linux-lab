#!/usr/bin/env bash
# Vendor a pinned mermaid.min.js into the docs site so pages never load it from a CDN.
# Fetches the npm tarball with curl (no Node.js) and verifies it against the registry's
# sha512 integrity before extracting, then repoints mkdocs.yml at the new file.
#
# Usage: tools/vendor-mermaid.sh <version>     (or: make vendor-mermaid MERMAID_VERSION=<version>)
set -euo pipefail

version=${1:?usage: tools/vendor-mermaid.sh <version>}
dest=docs/assets/javascripts/vendor
registry=https://registry.npmjs.org/mermaid

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "==> Looking up mermaid $version"
integrity=$(curl -fsSL "$registry/$version" |
  python3 -I -c 'import json, sys; print(json.load(sys.stdin)["dist"]["integrity"])')

echo "==> Downloading and verifying $integrity"
curl -fsSL -o "$tmp/mermaid.tgz" "$registry/-/mermaid-$version.tgz"
actual="sha512-$(openssl dgst -sha512 -binary "$tmp/mermaid.tgz" | base64 -w0)"
if [[ "$actual" != "$integrity" ]]; then
  echo "vendor-mermaid: integrity mismatch (got $actual)" >&2
  exit 1
fi

tar -xzf "$tmp/mermaid.tgz" -C "$tmp" package/dist/mermaid.min.js package/LICENSE
rm -f "$dest"/mermaid-*.min.js
install -Dm644 "$tmp/package/dist/mermaid.min.js" "$dest/mermaid-$version.min.js"
install -Dm644 "$tmp/package/LICENSE" "$dest/mermaid.LICENSE"
(cd "$dest" && sha256sum "mermaid-$version.min.js" >mermaid.sha256)

sed -i -E "s#(assets/javascripts/vendor/)mermaid-[0-9.]+\.min\.js#\1mermaid-$version.min.js#" mkdocs.yml
echo "==> Vendored $dest/mermaid-$version.min.js; mkdocs.yml updated"
