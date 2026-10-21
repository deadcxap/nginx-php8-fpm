#!/bin/sh
set -eu

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
cd "$workspace"
mkdir fixture app
cat > fixture/package.json <<'JSON'
{"name":"image-smoke-fixture","version":"1.0.0","bin":{"image-smoke-fixture":"cli.js"}}
JSON
cat > fixture/cli.js <<'JS'
#!/usr/bin/env node
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
assert.equal(crypto.randomBytes(16).length, 16);
assert.equal(crypto.createHash('sha256').update('hello').digest('hex'),
    '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824');
console.log('npm-smoke-ok');
JS
chmod +x fixture/cli.js
npm --version
npx --version
npm pack ./fixture --offline --ignore-scripts >/dev/null
cd app
printf '{"name":"image-smoke-app","version":"1.0.0","private":true}\n' > package.json
npm install ../image-smoke-fixture-1.0.0.tgz --offline --ignore-scripts --no-audit --no-fund
test "$(npx --offline --no -- image-smoke-fixture)" = npm-smoke-ok
echo 'Node crypto and offline npm pack/install/exec passed.'
