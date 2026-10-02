#!/bin/bash
# Fay – Faz 4: FayPool kaynak kodunu Sourcify (+ varsa Etherscan) üzerinde doğrular
set -e
cd "$(dirname "$0")"
export PATH="$HOME/.bun/bin:$PATH"
( cd scripts && bun install --silent )
bun run scripts/verify.ts
echo; echo "[İşlem tamamlandı]"
