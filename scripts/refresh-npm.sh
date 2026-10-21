#!/bin/sh
set -eu

npm install --global --engine-strict --ignore-scripts --no-audit --no-fund npm@latest
npm_dir="$(npm root --global)/npm"
dependency_dir=$(mktemp -d)
trap 'rm -rf "$dependency_dir"' EXIT

# npm ships bundled dependencies that can remain vulnerable even in npm@latest.
# Resolve its runtime dependency ranges afresh, preserving npm's own manifest.
# Use a separate directory: npm's source-only development workspaces are not
# published, and the running npm must stay intact until installation completes.
node - "$npm_dir" "$dependency_dir" <<'JS'
const fs = require('node:fs');
const path = require('node:path');
const manifest = require(path.join(process.argv[2], 'package.json'));
const runtime = { name: 'npm-runtime-dependencies', version: '1.0.0', private: true };
for (const key of ['engines', 'dependencies', 'optionalDependencies', 'peerDependencies', 'peerDependenciesMeta']) {
    if (manifest[key]) runtime[key] = manifest[key];
}
fs.writeFileSync(path.join(process.argv[3], 'package.json'), JSON.stringify(runtime));
JS
npm install --prefix "$dependency_dir" --omit=dev --package-lock=false \
    --engine-strict --ignore-scripts --no-audit --no-fund
rm -rf "$npm_dir/node_modules"
mv "$dependency_dir/node_modules" "$npm_dir/node_modules"
npm cache clean --force
npm --version
npx --version
