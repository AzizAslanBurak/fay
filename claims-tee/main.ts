/**
 * Fay – claims-tee CRE workflow (Confidential Workflow / TEE)
 * -----------------------------------------------------------
 * Gizli poliçelerin konumu zincirde yoktur; sadece keccak taahhüdü vardır.
 * Bu handler AWS Nitro enclave'inde çalışır (`handlerInTee`):
 *   1. DON üzerinden zinciri okur: son işlenen deprem + gizli poliçeler (taahhütler)
 *   2. Enclave içinde Vault DON'dan API anahtarını alır ve Policy Vault'tan konumları çeker
 *      → konumlar ve anahtar node operatörlerine hiç görünmez
 *   3. Taahhüdü doğrular, hiposantr mesafesinden ödeme kademesini hesaplar
 *   4. DON'a geri döner: sadece (poliçeId, kademe) listesi imzalanır ve FayPool'a yazılır
 *
 * Simülatör gerçek enclave değildir (debug); üretimde loglar enclave dışına çıkmaz.
 */
import {
  CronCapability,
  EVMClient,
  HTTPClient,
  handlerInTee,
  Runner,
  getNetwork,
  encodeCallMsg,
  bytesToHex,
  hexToBase64,
  type Runtime,
  type TeeRuntime,
} from "@chainlink/cre-sdk"
import {
  encodeAbiParameters,
  parseAbiParameters,
  encodeFunctionData,
  decodeFunctionResult,
  keccak256,
  zeroAddress,
  type Hex,
} from "viem"
import { FayPoolAbi } from "../contracts/abi/FayPool"

type EvmConfig = { chainName: string; fayPoolAddress: string; gasLimit: string }
type Config = {
  schedule: string
  vaultUrl: string // Policy Vault GET /policies
  vaultSecretId: string // Vault DON'daki API anahtarının adı
  evms: EvmConfig[]
}

type VaultRow = { policyId: number; latE6: number; lonE6: number; salt: Hex; commit: Hex }
type Result = { eventId: string; privatePolicies: number; evaluated: number; paidTiers: number[]; txHash?: string }

// FayPool.lastQuake() getter sırası (QuakeReport)
type Quake = {
  eventId: Hex
  eventTime: bigint
  latE6: number
  lonE6: number
  magX100: number
  depthKmX10: number
  fullRadiusKmX10: number
  halfRadiusKmX10: number
  cosLatE6: number
  sourcesAgreed: number
}

function call<T>(rt: Runtime<Config>, evm: EVMClient, pool: Hex, fn: any, args: any[] = []): T {
  const r = evm
    .callContract(rt, {
      call: encodeCallMsg({ from: zeroAddress, to: pool, data: encodeFunctionData({ abi: FayPoolAbi, functionName: fn, args } as any) }),
    })
    .result()
  return decodeFunctionResult({ abi: FayPoolAbi, functionName: fn, data: bytesToHex(r.data) } as any) as T
}

/** Sözleşmedeki _distanceSquaredMeters ile birebir aynı tamsayı aritmetiği (m²). */
function distance2Meters(pLatE6: number, pLonE6: number, q: Quake): bigint {
  const K = 111320n
  const abs = (x: bigint) => (x < 0n ? -x : x)
  const dLat = abs(BigInt(pLatE6) - BigInt(q.latE6))
  const dLon = abs(BigInt(pLonE6) - BigInt(q.lonE6))
  const latM = (dLat * K) / 1_000_000n
  const lonM = (((dLon * K) / 1_000_000n) * BigInt(q.cosLatE6)) / 1_000_000n
  const depthM = BigInt(q.depthKmX10) * 100n
  return latM * latM + lonM * lonM + depthM * depthM
}
function tierOf(pLatE6: number, pLonE6: number, q: Quake): number {
  const d2 = distance2Meters(pLatE6, pLonE6, q)
  const full = BigInt(q.fullRadiusKmX10) * 100n
  const half = BigInt(q.halfRadiusKmX10) * 100n
  if (d2 <= full * full) return 1
  if (d2 <= half * half) return 2
  return 0
}
const commitOf = (latE6: number, lonE6: number, salt: Hex): Hex =>
  keccak256(encodeAbiParameters(parseAbiParameters("int32 latE6, int32 lonE6, bytes32 salt"), [latE6, lonE6, salt]))

const onCronTrigger = (tee: TeeRuntime<Config>): Result => {
  const cfg = tee.config
  const evmCfg = cfg.evms[0]
  const network = getNetwork({ chainFamily: "evm", chainSelectorName: evmCfg.chainName })
  if (!network) throw new Error(`Bilinmeyen zincir: ${evmCfg.chainName}`)
  const evm = new EVMClient(network.chainSelector.selector)
  const pool = evmCfg.fayPoolAddress as Hex

  // 1) Zincir okumaları her zaman DON'da yapılır (gizli değil; zaten herkese açık veri)
  const don = tee.usingTheDons()
  const lq = call<any>(don, evm, pool, "lastQuake")
  const q: Quake = {
    eventId: lq[0],
    eventTime: lq[1],
    latE6: Number(lq[2]),
    lonE6: Number(lq[3]),
    magX100: Number(lq[4]),
    depthKmX10: Number(lq[5]),
    fullRadiusKmX10: Number(lq[6]),
    halfRadiusKmX10: Number(lq[7]),
    cosLatE6: Number(lq[8]),
    sourcesAgreed: Number(lq[9]),
  }
  const zero = "0x" + "0".repeat(64)
  if (!q.eventId || q.eventId === zero) {
    tee.log("Henüz işlenmiş deprem yok.")
    return { eventId: "none", privatePolicies: 0, evaluated: 0, paidTiers: [] }
  }
  if (call<boolean>(don, evm, pool, "claimsProcessed", [q.eventId])) {
    tee.log(`Olay ${q.eventId.slice(0, 10)}… için gizli poliçe ödemeleri zaten işlenmiş.`)
    return { eventId: q.eventId, privatePolicies: 0, evaluated: 0, paidTiers: [] }
  }

  const n = Number(call<bigint>(don, evm, pool, "policyCount"))
  const privateIds: number[] = []
  const commits = new Map<number, Hex>()
  for (let i = 1; i <= n; i++) {
    const p = call<any>(don, evm, pool, "policies", [BigInt(i)])
    // [holder, latE6, lonE6, coverage, expiresAt, active, isPrivate, locationCommit]
    if (p[5] && p[6]) {
      privateIds.push(i)
      commits.set(i, p[7] as Hex)
    }
  }
  tee.log(`Deprem M${q.magX100 / 100} @ ${q.latE6 / 1e6},${q.lonE6 / 1e6} · aktif gizli poliçe: ${privateIds.length}`)
  if (privateIds.length === 0) return { eventId: q.eventId, privatePolicies: 0, evaluated: 0, paidTiers: [] }

  // 2) ENCLAVE: API anahtarı yalnızca burada açılır, vault isteği enclave'den çıkar
  const apiKey = tee.getSecret({ id: cfg.vaultSecretId }).result().value
  const resp = new HTTPClient()
    .sendRequest(tee, {
      url: `${cfg.vaultUrl}?ids=${privateIds.join(",")}`,
      method: "GET",
      multiHeaders: { "x-api-key": { values: [apiKey] } },
    })
    .result()
  if (resp.statusCode !== 200) throw new Error(`Policy Vault HTTP ${resp.statusCode}`)
  const rows = (JSON.parse(new TextDecoder().decode(resp.body)) as { policies: VaultRow[] }).policies

  // 3) ENCLAVE: taahhüt doğrula + kademe hesapla (konumlar enclave dışına ÇIKMAZ)
  const ids: bigint[] = []
  const tiers: number[] = []
  for (const r of rows) {
    const expected = commits.get(r.policyId)
    if (!expected || commitOf(r.latE6, r.lonE6, r.salt).toLowerCase() !== expected.toLowerCase()) continue // sahte/uyumsuz kayıt
    const t = tierOf(r.latE6, r.lonE6, q)
    if (t === 0) continue
    ids.push(BigInt(r.policyId))
    tiers.push(t)
  }
  // Simülasyon logu (üretimde kaldırılır): sadece sayılar, konum yok
  tee.log(`Enclave: ${rows.length} kayıt doğrulandı, ${ids.length} poliçe ödeme kademesine girdi`)

  if (ids.length === 0) {
    return { eventId: q.eventId, privatePolicies: privateIds.length, evaluated: rows.length, paidTiers: [] }
  }

  // 4) DON: sadece (id, kademe) listesi imzalanır ve yazılır
  const payload = encodeAbiParameters(parseAbiParameters("bytes32 eventId, uint256[] policyIds, uint8[] tiers"), [q.eventId, ids, tiers])
  const wrapped = encodeAbiParameters(parseAbiParameters("uint8 kind, bytes payload"), [3, payload])
  const report = don
    .report({ encodedPayload: hexToBase64(wrapped), encoderName: "evm", signingAlgo: "ecdsa", hashingAlgo: "keccak256" })
    .result()
  const res = evm.writeReport(don, { receiver: evmCfg.fayPoolAddress, report, gasConfig: { gasLimit: evmCfg.gasLimit } }).result()
  const txHash = bytesToHex(res.txHash || new Uint8Array(32))
  don.log(`writeReport durumu: ${String(res.txStatus)} tx: ${txHash}`)
  if (res.errorMessage) don.log(`writeReport hata: ${res.errorMessage}`)
  return { eventId: q.eventId, privatePolicies: privateIds.length, evaluated: rows.length, paidTiers: tiers, txHash }
}

const initWorkflow = (config: Config) => {
  const cron = new CronCapability()
  // Kabul edilen enclave: AWS Nitro, us-west-2 (şu an kayıtlı tek TEE)
  return [handlerInTee(cron.trigger({ schedule: config.schedule }), onCronTrigger, [{ tee: "nitro", regions: ["us-west-2"] }])]
}

export async function main() {
  const runner = await Runner.newRunner<Config>()
  await runner.run(initWorkflow)
}
