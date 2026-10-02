/**
 * Fay Policy Vault – gizli poliçelerin konumunu zincir DIŞINDA tutan küçük servis.
 *   bun run vault/server.ts        (varsayılan port 8787)
 *
 * - POST /policies  { policyId, latE6, lonE6, salt, commit }  → kaydeder (commit doğrulanır)
 * - GET  /policies?ids=1,2,3   (header: x-api-key)             → konumları döner
 *
 * Gerçek dağıtımda bu servis bir bulut fonksiyonu olur ve API anahtarı sadece Chainlink Vault DON'da durur;
 * claims-tee workflow'u anahtarı yalnızca enclave içinde alır. Prototip: JSON dosyası.
 */
import { readFileSync, writeFileSync, existsSync } from "node:fs"
import { resolve, dirname } from "node:path"
import { fileURLToPath } from "node:url"
import { keccak256, encodeAbiParameters, parseAbiParameters, type Hex } from "viem"

const DIR = dirname(fileURLToPath(import.meta.url))
const DB = resolve(DIR, "policies.json")
const PORT = Number(process.env.VAULT_PORT || 8787)
const API_KEY = process.env.VAULT_API_KEY_ALL || process.env.VAULT_API_KEY || "dev-vault-key"

type Row = { policyId: number; latE6: number; lonE6: number; salt: Hex; commit: Hex; createdAt: string }
const load = (): Record<string, Row> => (existsSync(DB) ? JSON.parse(readFileSync(DB, "utf8")) : {})
const save = (db: Record<string, Row>) => writeFileSync(DB, JSON.stringify(db, null, 2) + "\n")

export const commitOf = (latE6: number, lonE6: number, salt: Hex): Hex =>
  keccak256(encodeAbiParameters(parseAbiParameters("int32 latE6, int32 lonE6, bytes32 salt"), [latE6, lonE6, salt]))

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, x-api-key",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
}
const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json", ...cors } })

Bun.serve({
  port: PORT,
  async fetch(req) {
    const url = new URL(req.url)
    if (req.method === "OPTIONS") return new Response(null, { headers: cors })

    if (url.pathname === "/health") return json({ ok: true, policies: Object.keys(load()).length })

    if (url.pathname === "/policies" && req.method === "POST") {
      const b = (await req.json()) as Partial<Row>
      if (!b.policyId || typeof b.latE6 !== "number" || typeof b.lonE6 !== "number" || !b.salt || !b.commit) {
        return json({ error: "policyId, latE6, lonE6, salt, commit gerekli" }, 400)
      }
      const expected = commitOf(b.latE6, b.lonE6, b.salt as Hex)
      if (expected.toLowerCase() !== String(b.commit).toLowerCase()) return json({ error: "commit uyuşmuyor", expected }, 400)
      const db = load()
      db[String(b.policyId)] = { policyId: b.policyId, latE6: b.latE6, lonE6: b.lonE6, salt: b.salt as Hex, commit: expected, createdAt: new Date().toISOString() }
      save(db)
      return json({ ok: true, policyId: b.policyId })
    }

    if (url.pathname === "/policies" && req.method === "GET") {
      if (req.headers.get("x-api-key") !== API_KEY) return json({ error: "unauthorized" }, 401)
      const ids = (url.searchParams.get("ids") || "").split(",").filter(Boolean)
      const db = load()
      const rows = ids.length ? ids.map((i) => db[i]).filter(Boolean) : Object.values(db)
      return json({ policies: rows })
    }

    return json({ error: "not found" }, 404)
  },
})

console.log(`Fay Policy Vault → http://localhost:${PORT}  (API anahtarı: ${API_KEY === "dev-vault-key" ? "dev-vault-key [varsayılan]" : "ayarlı"})`)
