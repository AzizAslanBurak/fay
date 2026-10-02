#!/bin/bash
# Policy Vault'u çalıştırır (uygulamadan gizli poliçe alırken açık olmalı). Ctrl+C ile durdur.
cd "$(dirname "$0")"
export PATH="$HOME/.bun/bin:$PATH"
( cd vault && bun install >/dev/null )
VAULT_API_KEY_ALL=dev-vault-key bun run vault/server.ts
