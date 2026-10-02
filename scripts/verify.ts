/**
 * Fay – FayPool kaynak doğrulama (Faz 4)
 *  1. Sourcify (API anahtarı gerekmez) – her zaman denenir.
 *  2. Etherscan v2 – .env'de ETHERSCAN_API_KEY varsa.
 * Derleme ayarları deploy.ts ile birebir aynıdır (aynı solc paketi, optimizer 200).
 */
import { existsSync, readFileSync } from "node:fs"
import { resolve, dirname } from "node:path"
import { fileURLToPath } from "node:url"
import { encodeAbiParameters } from "viem"
// @ts-ignore
import solc from "solc"

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..")
const CHAIN_ID = 11155111
const dep = JSON.parse(readFileSync(resolve(ROOT, "deployments/sepolia.json"), "utf8"))
const ADDRESS: string = dep.fayPool
const FORWARDER: string = dep.forwarder

function envKey(k: string): string | undefined {
  const p = resolve(ROOT, ".env")
  if (!existsSync(p)) return
  const m = readFileSync(p, "utf8").match(new RegExp(`^\\s*${k}\\s*=\\s*(.+)\\s*$`, "m"))
  return m?.[1]?.trim() || undefined
}

// ---- Kaynakları topla (deploy.ts'in import çözümüyle aynı birim adları)
const contractsDir = resolve(ROOT, "contracts")
const nm = resolve(ROOT, "scripts", "node_modules")
const sources: Record<string, { content: string }> = {}
const queue = ["FayPool.sol"]
while (queue.length) {
  const unit = queue.shift()!
  if (sources[unit]) continue
  const local = resolve(contractsDir, unit)
  const path = existsSync(local) ? local : resolve(nm, unit)
  if (!existsSync(path)) throw new Error(`Kaynak bulunamadı: ${unit}`)
  const content = readFileSync(path, "utf8")
  sources[unit] = { content }
  for (const m of content.matchAll(/import\s+(?:\{[^}]*\}\s+from\s+)?"([^"]+)"/g)) {
    const imp = m[1]
    let target: string
    if (imp.startsWith(".")) {
      // aynı dizine göre çöz (deploy.ts'te solc "./X.sol" -> "X.sol" olarak normalize eder)
      const base = unit.includes("/") ? unit.slice(0, unit.lastIndexOf("/") + 1) : ""
      target = new URL(imp, "file:///" + base).pathname.slice(1)
    } else target = imp
    queue.push(target)
  }
}
const input = {
  language: "Solidity",
  sources,
  settings: { optimizer: { enabled: true, runs: 200 }, outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } } },
}
const out = JSON.parse(solc.compile(JSON.stringify(input)))
const errs = (out.errors ?? []).filter((e: any) => e.severity === "error")
if (errs.length) { errs.forEach((e: any) => console.error(e.formattedMessage)); process.exit(1) }

const longVer: string = solc.version() // ör. 0.8.37+commit.abcdef12.Emscripten.clang
const shortVer = longVer.replace(/\.Emscripten.*$/, "") // 0.8.37+commit.abcdef12
const compilerVersion = "v" + shortVer
const ctorArgs = encodeAbiParameters([{ type: "address" }], [FORWARDER as `0x${string}`]).slice(2)
console.log(`Sözleşme : ${ADDRESS}\nDerleyici: ${compilerVersion}\nKaynaklar: ${Object.keys(sources).join(", ")}`)

// ---- 1) Sourcify
async function sourcifyStatus(): Promise<string | null> {
  const r = await fetch(`https://sourcify.dev/server/v2/contract/${CHAIN_ID}/${ADDRESS}`)
  if (!r.ok) return null
  const j: any = await r.json().catch(() => ({}))
  return j.match ?? null
}
async function sourcify() {
  console.log("\n==> Sourcify doğrulaması...")
  const already = await sourcifyStatus()
  if (already) { console.log(`  Zaten doğrulanmış ✅ (${already}) https://repo.sourcify.dev/${CHAIN_ID}/${ADDRESS}`); return true }
  const r = await fetch(`https://sourcify.dev/server/v2/verify/${CHAIN_ID}/${ADDRESS}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ stdJsonInput: input, compilerVersion: shortVer, contractIdentifier: "FayPool.sol:FayPool" }),
  })
  const j: any = await r.json().catch(() => ({}))
  if (r.status === 409) { console.log("  Zaten doğrulanmış ✅"); return true }
  if (!r.ok) { console.log(`  Sourcify hata ${r.status}: ${JSON.stringify(j)}`); return false }
  const id = j.verificationId
  for (let i = 0; i < 60; i++) {
    await new Promise((s) => setTimeout(s, 5000))
    const st: any = await (await fetch(`https://sourcify.dev/server/v2/verify/${id}`)).json().catch(() => ({}))
    const done = st.isJobCompleted === true || st.status === "completed" || st.contract?.match || st.error
    if (!done) { const m = await sourcifyStatus(); if (m) { console.log(`  Sourcify ✅ (${m}) https://repo.sourcify.dev/${CHAIN_ID}/${ADDRESS}`); return true } ; continue }
    if (st.contract?.match) { console.log(`  Sourcify ✅ (${st.contract.match}) https://repo.sourcify.dev/${CHAIN_ID}/${ADDRESS}`); return true }
    console.log(`  Sourcify eşleşmedi: ${JSON.stringify(st.error ?? st)}`); return false
  }
  console.log("  Sourcify zaman aşımı; birkaç dakika sonra tekrar çalıştır."); return false
}

// ---- 2) Etherscan v2
async function etherscan() {
  const key = envKey("ETHERSCAN_API_KEY")
  if (!key) { console.log("\n==> Etherscan: .env'de ETHERSCAN_API_KEY yok, atlandı (Sourcify yeterli; istersen ekle)."); return }
  console.log("\n==> Etherscan doğrulaması...")
  const base = `https://api.etherscan.io/v2/api?chainid=${CHAIN_ID}`
  const form = new URLSearchParams({
    apikey: key, module: "contract", action: "verifysourcecode",
    contractaddress: ADDRESS, sourceCode: JSON.stringify(input), codeformat: "solidity-standard-json-input",
    contractname: "FayPool.sol:FayPool", compilerversion: compilerVersion, constructorArguements: ctorArgs,
  })
  const j: any = await (await fetch(base, { method: "POST", body: form })).json()
  if (j.status !== "1") {
    if (String(j.result).toLowerCase().includes("already verified")) { console.log("  Zaten doğrulanmış ✅"); return }
    console.log(`  Etherscan hata: ${j.result}`); return
  }
  const guid = j.result
  for (let i = 0; i < 20; i++) {
    await new Promise((s) => setTimeout(s, 5000))
    const st: any = await (await fetch(`${base}&module=contract&action=checkverifystatus&guid=${guid}&apikey=${key}`)).json()
    if (st.result === "Pending in queue") continue
    if (st.status === "1" || String(st.result).includes("Already Verified")) { console.log(`  Etherscan ✅ https://sepolia.etherscan.io/address/${ADDRESS}#code`); return }
    console.log(`  Etherscan sonucu: ${st.result}`); return
  }
  console.log("  Etherscan zaman aşımı; birkaç dakika sonra tekrar dene.")
}

const ok = await sourcify()
await etherscan()
if (!ok) process.exit(1)
