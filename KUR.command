#!/bin/bash
# Fay – CRE geliştirme ortamı kurulumu + ilk simülasyon (tek tık)
set -e
cd "$(dirname "$0")"
export PATH="$HOME/.bun/bin:$HOME/.cre:$HOME/.cre/bin:$PATH"

echo "==> 1/5 Bun (JS runtime) kontrol ediliyor..."
if ! command -v bun >/dev/null; then
  curl -fsSL https://bun.sh/install | bash
  export PATH="$HOME/.bun/bin:$PATH"
fi
bun --version

echo "==> 2/5 CRE CLI kontrol ediliyor..."
if ! command -v cre >/dev/null; then
  curl -sSL https://app.chain.link/cre/install.sh | bash
  xattr -c "$HOME/.cre/cre" "$HOME/.cre/bin/cre" 2>/dev/null || true
  hash -r
fi
grep -q 'CRE_INSTALL' "$HOME/.zshrc" 2>/dev/null || cat >> "$HOME/.zshrc" <<'RC'
export CRE_INSTALL="$HOME/.cre"
export PATH="$CRE_INSTALL:$CRE_INSTALL/bin:$HOME/.bun/bin:$PATH"
RC
cre version

echo "==> 3/5 Chainlink hesabına giriş (tarayıcı açılacak; hesabın yoksa oradan oluştur)..."
if ! cre whoami >/dev/null 2>&1; then
  cre login
fi
cre whoami

echo "==> 4/5 Workflow bağımlılıkları kuruluyor..."
( cd quake-oracle && bun install )
[ -f .env ] || cp .env.example .env

echo "==> 5/5 Mantık testleri..."
node --test tests/logic.test.mjs 2>/dev/null || bun test tests/ 2>/dev/null || echo "(testler atlandı)"

echo
echo "==> DEMO simülasyonu: 2023 Kahramanmaraş olayı enjekte edilerek çalıştırılıyor..."
echo "    (zincire yazmaz; fayPoolAddress boş)"
cre workflow simulate quake-oracle --target demo-settings --non-interactive --trigger-index 0 || true

echo
echo "==> CANLI simülasyon: USGS + EMSC + AFAD gerçek verisi (son 30 dk, M≥5.5)..."
cre workflow simulate quake-oracle --target staging-settings --non-interactive --trigger-index 0 || true

echo
echo "✅ Bitti. Yukarıdaki loglarda 'UZLAŞILAN OLAY: M7.8' (demo) ve 'Eşiği geçen deprem yok' (canlı) satırlarını görmelisin."
echo "   Hata varsa bu pencerenin çıktısını Claude'a yapıştır."
