#!/bin/bash
# Fay – havuzu test cüzdanından fonla (varsayılan 0.03 ETH). Kullanım: çift tık.
set -e
cd "$(dirname "$0")"
export PATH="$HOME/.bun/bin:$PATH"
( cd scripts && bun install --silent )
bun run scripts/fund.ts "${1:-0.03}"
echo; echo "[İşlem tamamlandı]"
