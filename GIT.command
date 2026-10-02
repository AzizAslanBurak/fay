#!/bin/bash
# Fay – projeyi GitHub'a koy (tek tık). .env ve anahtarlar asla gönderilmez.
set -e
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if [ ! -d .git ]; then
  git init -b main >/dev/null
  echo "==> git deposu oluşturuldu"
fi
git config user.name  >/dev/null 2>&1 || git config user.name "Aziz Aslan"
git config user.email >/dev/null 2>&1 || git config user.email "azizaslanburak@gmail.com"

# Güvenlik: .env kesinlikle takip dışı olmalı
if ! git check-ignore -q .env; then echo "❌ .env ignore edilmemiş, durduruldu."; exit 1; fi
# Eski kalmış kilit dosyası (çalışan git yoksa) temizlenir
if [ -f .git/index.lock ] && ! pgrep -x git >/dev/null; then rm -f .git/index.lock; fi
git add -A
git status --short | head -40
git commit -qm "Fay: parametric earthquake insurance on Chainlink CRE (quake-oracle workflow, FayPool, Flutter web)" || echo "(değişiklik yok)"
echo "==> commit tamam"

if git remote get-url origin >/dev/null 2>&1; then
  git push -u origin main
  echo "✅ GitHub'a gönderildi: $(git remote get-url origin)"
  exit 0
fi

if command -v gh >/dev/null; then
  gh auth status >/dev/null 2>&1 || gh auth login
  gh repo create fay --public --source=. --remote=origin --push --description "Parametric earthquake insurance on Chainlink CRE – automatic payouts from USGS/EMSC/AFAD consensus"
  echo "✅ GitHub'a gönderildi: $(git remote get-url origin)"
else
  echo
  echo "GitHub CLI (gh) yok. İki seçenek:"
  echo "  a) Terminal'de:  brew install gh   → sonra bu dosyaya tekrar çift tıkla"
  echo "  b) github.com'da 'fay' adında BOŞ bir repo aç (README ekleme), URL'sini buraya yapıştır:"
  read -r URL
  if [ -n "$URL" ]; then
    git remote add origin "$URL"
    git push -u origin main
    echo "✅ GitHub'a gönderildi: $URL"
  fi
fi
