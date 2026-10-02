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
echo "==> Workflow bağımlılıkları..."
( cd pool-guardian && bun install )

echo
echo "==> Zincir üstü DEMO 1/3: 2023 Kahramanmaraş raporu FayPool'a yazılıyor (--broadcast)..."
cre workflow simulate quake-oracle --target demo-settings --broadcast --non-interactive --trigger-index 0

echo
echo "==> Zincir üstü DEMO 2/3: pool-guardian satışları DURDURUYOR (devre kesici)..."
cre workflow simulate pool-guardian --target demo-settings --broadcast --non-interactive --trigger-index 0

echo
echo "==> Zincir üstü DEMO 3/3: pool-guardian satışları yeniden AÇIYOR..."
sleep 5
cre workflow simulate pool-guardian --target resume-settings --broadcast --non-interactive --trigger-index 0

echo
echo "==> Canlı bekçi kontrolü (müdahale gerekmemeli)..."
cre workflow simulate pool-guardian --target staging-settings --non-interactive --trigger-index 0

echo
echo "✅ Bitti. Üç --broadcast adımında da 'writeReport durumu: 2' (SUCCESS) ve tx hash görmelisin."
echo "   Etherscan'de FayPool adresindeki 'Events' sekmesinde PolicyPaid olayını görebilirsin."
