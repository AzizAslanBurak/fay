#!/bin/bash
# pool-guardian demo: satışları yeniden AÇ + canlı kontrol
set -e
cd "$(dirname "$0")"
export PATH="$HOME/.bun/bin:$HOME/.cre:$HOME/.cre/bin:$PATH"
echo "==> pool-guardian: satışları yeniden AÇIYOR (--broadcast)..."
cre workflow simulate pool-guardian --target resume-settings --broadcast --non-interactive --trigger-index 0
echo
echo "==> Canlı bekçi kontrolü (müdahale gerekmemeli)..."
cre workflow simulate pool-guardian --target staging-settings --non-interactive --trigger-index 0
echo
echo "✅ Bitti."
