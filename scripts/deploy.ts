/**
 * Fay – Sepolia deploy scripti (bun run scripts/deploy.ts)
 *
 * 1. .env'de CRE_ETH_PRIVATE_KEY yoksa yeni bir TEST cüzdanı üretir ve kaydeder.
 * 2. Bakiye 0 ise faucet talimatı verip çıkar.
 * 3. FayPool.sol'u derler (solc-js), MockKeystoneForwarder ile Sepolia'ya deploy eder.
 * 4. Havuzu fonlar, Pazarcık için örnek bir poliçe alır.
 * 5. Adresi config.demo.json / config.staging.json'a ve deployments/sepolia.json'a yazar.
 * Tekrar çalıştırılırsa deploy'u atlar (idempotent).
 */
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs"
import { resolve, dirname } from "node:path"
import { fileURLToPath } from "node:url"
import {
  createPublicClient,
  createWalletClient,
  http,
  formatEther,
  parseEther,
  encodeFunctionData,
  type Hex,
} from "viem"
import { privateKeyToAccount, generatePrivateKey } from "viem/accounts"
import { keccak256, encodeAbiParameters, parseAbiParameters, toHex } from "viem"
import { sepolia } from "viem/chains"
// @ts-ignore – solc-js'in tipi yok
import solc from "solc"

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..")
const ENV_PATH = resolve(ROOT, ".env")
const RPC_URL = process.env.SEPOLIA_RPC_URL || "https://ethereum-sepolia-rpc.publicnode.com"
// CRE simülasyonu (--broadcast) MockKeystoneForwarder üzerinden yazar.
const MOCK_FORWARDER_SEPOLIA = "0x15fC6ae953E024d975e77382eEeC56A9101f9F88"
const FUND_ETH = "0.003"
const COVERAGE_ETH = "0.002" // örnek poliçe teminatı; prim = %5 = 0.0005 ETH
const PAZARCIK = { latE6: 37_490_000, lonE6: 37_300_000 }

// ---------------------------------------------------------------- .env
function readEnv(): Record<string, string> {
  if (!existsSync(ENV_PATH)) return {}
  const out: Record<string, string> = {}
  for (const line of readFileSync(ENV_PATH, "utf8").split("\n")) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/)
    if (m) out[m[1]] = m[2]
  }
  return out
}
function writeEnvKey(key: string, value: string) {
  let txt = existsSync(ENV_PATH) ? readFileSync(ENV_PATH, "utf8") : ""
  const re = new RegExp(`^${key}=.*$`, "m")
  txt = re.test(txt) ? txt.replace(re, `${key}=${value}`) : txt.trimEnd() + `\n${key}=${value}\n`
  writeFileSync(ENV_PATH, txt)
}

// ---------------------------------------------------------------- Derleme
function compileFayPool(): { abi: any; bytecode: Hex } {
  const contractsDir = resolve(ROOT, "contracts")
  const nodeModules = resolve(ROOT, "scripts", "node_modules")
  const read = (p: string) => readFileSync(p, "utf8")
  const input = {
    language: "Solidity",
    sources: { "FayPool.sol": { content: read(resolve(contractsDir, "FayPool.sol")) } },
    settings: {
      optimizer: { enabled: true, runs: 200 },
      outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } },
    },
  }
  const findImports = (path: string) => {
    const local = resolve(contractsDir, path)
    if (existsSync(local)) return { contents: read(local) }
    const nm = resolve(nodeModules, path)
    if (existsSync(nm)) return { contents: read(nm) }
    return { error: `Import bulunamadı: ${path}` }
  }
  const out = JSON.parse(solc.compile(JSON.stringify(input), { import: findImports }))
  const errors = (out.errors ?? []).filter((e: any) => e.severity === "error")
  if (errors.length) {
    for (const e of errors) console.error(e.formattedMessage)
    throw new Error("Solidity derleme hatası")
  }
  const c = out.contracts["FayPool.sol"]["FayPool"]
  return { abi: c.abi, bytecode: ("0x" + c.evm.bytecode.object) as Hex }
}

// ---------------------------------------------------------------- Yardımcılar
function setPoolAddressInConfigs(address: string, deployBlock?: bigint) {
  for (const wf of ["quake-oracle", "pool-guardian", "claims-tee"]) {
    for (const f of ["config.demo.json", "config.demo2.json", "config.staging.json", "config.production.json", "config.resume.json"]) {
      const p = resolve(ROOT, wf, f)
      if (!existsSync(p)) continue
      const cfg = JSON.parse(readFileSync(p, "utf8"))
      cfg.evms[0].fayPoolAddress = address
      writeFileSync(p, JSON.stringify(cfg, null, 2) + "\n")
    }
  }
  // Flutter uygulaması
  const dart = resolve(ROOT, "app", "lib", "config.dart")
  if (existsSync(dart)) {
    let d = readFileSync(dart, "utf8")
    d = d.replace(/fayPoolAddress = '0x[0-9a-fA-F]{40}'/, `fayPoolAddress = '${address}'`)
    if (deployBlock) d = d.replace(/deployBlock = \d+/, `deployBlock = ${deployBlock}`)
    writeFileSync(dart, d)
  }
}

async function main() {
  // 1) Cüzdan
  const env = readEnv()
  let pk = (env.CRE_ETH_PRIVATE_KEY || "").trim()
  if (!pk) {
    const fresh = generatePrivateKey()
    pk = fresh.slice(2)
    writeEnvKey("CRE_ETH_PRIVATE_KEY", pk)
    console.log("Yeni TEST cüzdanı üretildi ve .env dosyasına kaydedildi (sadece Sepolia için kullan).")
  }
  const account = privateKeyToAccount(("0x" + pk) as Hex)
  const publicClient = createPublicClient({ chain: sepolia, transport: http(RPC_URL) })
  const wallet = createWalletClient({ account, chain: sepolia, transport: http(RPC_URL) })

  const balance = await publicClient.getBalance({ address: account.address })
  console.log(`\nTest cüzdanı: ${account.address}`)
  console.log(`Sepolia bakiyesi: ${formatEther(balance)} ETH`)

  // Daha önce deploy edildiyse sadece gas gerekir; değilse fonlama + gas.
  const alreadyDeployed = existsSync(resolve(ROOT, "deployments", "sepolia.json"))
  const need = alreadyDeployed ? parseEther("0.005") : parseEther(FUND_ETH) + parseEther("0.006")
  if (balance < need) {
    console.log(`\n⛽ Yetersiz bakiye. En az ${formatEther(need)} Sepolia ETH gerekiyor.`)
    console.log("   1) https://faucets.chain.link  → Ethereum Sepolia → yukarıdaki adresi yapıştır → Chainlink hesabınla iste")
    console.log("   2) Para gelince DEPLOY.command'a tekrar çift tıkla.")
    process.exit(2)
  }

  // 2) Daha önce deploy edildi mi?
  const depDir = resolve(ROOT, "deployments")
  const depFile = resolve(depDir, "sepolia.json")
  let poolAddress: Hex | undefined
  let deployBlock: bigint | undefined
  if (existsSync(depFile)) {
    const d = JSON.parse(readFileSync(depFile, "utf8"))
    const code = await publicClient.getCode({ address: d.fayPool })
    if (code && code !== "0x") {
      poolAddress = d.fayPool
      console.log(`\nFayPool zaten deploy edilmiş: ${poolAddress} (atlanıyor)`)
    }
  }

  const { abi, bytecode } = compileFayPool()

  // 3) Deploy
  if (!poolAddress) {
    console.log("\nFayPool derlendi, Sepolia'ya deploy ediliyor...")
    const hash = await wallet.deployContract({ abi, bytecode, args: [MOCK_FORWARDER_SEPOLIA] })
    console.log(`  tx: https://sepolia.etherscan.io/tx/${hash}`)
    const rcpt = await publicClient.waitForTransactionReceipt({ hash })
    if (!rcpt.contractAddress) throw new Error("Deploy başarısız")
    poolAddress = rcpt.contractAddress
    deployBlock = rcpt.blockNumber
    console.log(`  FayPool: https://sepolia.etherscan.io/address/${poolAddress}`)
    mkdirSync(depDir, { recursive: true })
    writeFileSync(
      depFile,
      JSON.stringify(
        { network: "sepolia", fayPool: poolAddress, forwarder: MOCK_FORWARDER_SEPOLIA, deployer: account.address, deployBlock: Number(deployBlock), version: 2, deployedAt: new Date().toISOString() },
        null,
        2
      ) + "\n"
    )

    // 4) Fonla + örnek poliçe
    console.log(`\nHavuz fonlanıyor (${FUND_ETH} ETH)...`)
    const h1 = await wallet.sendTransaction({
      to: poolAddress,
      value: parseEther(FUND_ETH),
      data: encodeFunctionData({ abi, functionName: "fund" }),
    })
    await publicClient.waitForTransactionReceipt({ hash: h1 })

    const coverage = parseEther(COVERAGE_ETH)
    const premium = (await publicClient.readContract({ address: poolAddress, abi, functionName: "quotePremium", args: [coverage] })) as bigint
    console.log(`Örnek poliçe alınıyor: Pazarcık, teminat ${COVERAGE_ETH} ETH, prim ${formatEther(premium)} ETH...`)
    const h2 = await wallet.writeContract({
      address: poolAddress,
      abi,
      functionName: "buyPolicy",
      args: [PAZARCIK.latE6, PAZARCIK.lonE6, coverage],
      value: premium,
    })
    await publicClient.waitForTransactionReceipt({ hash: h2 })

    // Gizli demo poliçesi: Antakya (konum zincire gitmez; taahhüt + Policy Vault kaydı)
    const ANTAKYA = { latE6: 36_200_000, lonE6: 36_160_000 }
    const saltBytes = new Uint8Array(32)
    crypto.getRandomValues(saltBytes)
    const salt = toHex(saltBytes)
    const commit = keccak256(encodeAbiParameters(parseAbiParameters("int32 latE6, int32 lonE6, bytes32 salt"), [ANTAKYA.latE6, ANTAKYA.lonE6, salt]))
    console.log(`Gizli demo poliçesi alınıyor: Antakya (zincirde sadece taahhüt ${commit.slice(0, 10)}…)...`)
    const h3 = await wallet.writeContract({ address: poolAddress, abi, functionName: "buyPolicyPrivate", args: [commit, coverage], value: premium })
    await publicClient.waitForTransactionReceipt({ hash: h3 })
    const pid = (await publicClient.readContract({ address: poolAddress, abi, functionName: "policyCount" })) as bigint
    const vaultDb = resolve(ROOT, "vault", "policies.json")
    const db = existsSync(vaultDb) ? JSON.parse(readFileSync(vaultDb, "utf8")) : {}
    db[String(pid)] = { policyId: Number(pid), latE6: ANTAKYA.latE6, lonE6: ANTAKYA.lonE6, salt, commit, createdAt: new Date().toISOString() }
    writeFileSync(vaultDb, JSON.stringify(db, null, 2) + "\n")
    console.log(`  Policy Vault'a yazıldı: poliçe #${pid}`)
  }

  // 5) Config'leri güncelle
  setPoolAddressInConfigs(poolAddress, deployBlock)
  const active = await publicClient.readContract({ address: poolAddress, abi, functionName: "activePolicyCount" })
  const poolBal = await publicClient.getBalance({ address: poolAddress })
  console.log(`\n✅ Hazır. FayPool ${poolAddress} | aktif poliçe: ${active} | kasa: ${formatEther(poolBal)} ETH`)
  console.log("   config.demo.json ve config.staging.json güncellendi.")
}

main().catch((e) => {
  console.error("\n❌ Hata:", e.message || e)
  process.exit(1)
})
