#!/bin/bash
# Fay – Flutter Web uygulamasını çalıştır (tek tık). Normal Chrome'unda açılır (MetaMask uzantısı çalışsın diye).
set -e
cd "$(dirname "$0")/app"
export PATH="$HOME/development/flutter/bin:$HOME/flutter/bin:$PATH"
if ! command -v flutter >/dev/null; then
  echo "flutter bulunamadı. Flutter'ın kurulu olduğu yolu Claude'a söyle."; exit 1
fi
flutter --version >/dev/null 2>&1 || true
[ -d web ] || flutter create --platforms web --project-name fay_app . >/dev/null
flutter pub get
echo
echo "==> http://localhost:8080 adresinde başlatılıyor (Ctrl+C ile durdur)..."
( sleep 25 && open "http://localhost:8080" ) &
flutter run -d web-server --web-port 8080 --web-hostname localhost
