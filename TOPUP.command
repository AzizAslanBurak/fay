#!/bin/bash
# Test cüzdanından MetaMask hesabına Sepolia ETH aktarır (tek tık)
cd "$(dirname "$0")"
export PATH="$HOME/.bun/bin:$PATH"
DEFAULT_TO="0x93B7974E7A3af360b255bF6Fff97d0E3EE7D826E"
echo "Alıcı adres [Enter = $DEFAULT_TO]:"
read -r TO
TO="${TO:-$DEFAULT_TO}"
echo "Miktar ETH [Enter = 0.01]:"
read -r AMT
AMT="${AMT:-0.01}"
bun run scripts/send.ts "$TO" "$AMT"
echo
echo "Bu pencereyi kapatabilirsin."
