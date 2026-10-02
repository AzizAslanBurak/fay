#!/bin/bash
# Fay – Faz 1: Sepolia'ya deploy + zincir üstü demo (tek tık)
set -e
cd "$(dirname "$0")"
export PATH="$HOME/.bun/bin:$HOME/.cre:$HOME/.cre/bin:$PATH"

echo "==> Script bağımlılıkları (solc, viem, openzeppelin)..."
( cd scripts && bun install )

echo
echo "==> Cüzdan / deploy / fonlama / örnek poliçe..."
set +e
bun run scripts/deploy.ts
RC=$?
set -e
if [ $RC -eq 2 ]; then
  echo
  echo "Faucet'ten Sepolia ETH aldıktan sonra bu dosyaya tekrar çift tıkla."
  exit 0
elif [ $RC -ne 0 ]; then
  echo "Deploy başarısız (kod $RC). Çıktıyı Claude'a yapıştır."
  exit $RC
fi

echo
echo "==> Zincir üstü DEMO: 2023 Kahramanmaraş raporu FayPool'a yazılıyor (--broadcast)..."
cre workflow simulate quake-oracle --target demo-settings --broadcast --non-interactive --trigger-index 0

echo
echo "✅ Bitti. Yukarıda 'writeReport durumu: ... SUCCESS' ve bir tx hash görmelisin."
echo "   Etherscan'de FayPool adresindeki 'Events' sekmesinde PolicyPaid olayını görebilirsin."
