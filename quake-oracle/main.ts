/**
 * Fay – quake-oracle CRE workflow
 * --------------------------------
 * Cron ile tetiklenir. Her DON node'u USGS + EMSC + AFAD'ı bağımsız okur, bölge ve
 * eşik filtresi uygular, en güçlü depremi seçer. Node sonuçları alan-bazlı uzlaşıyla
 * (medyan / identical) birleştirilir. Eşiği geçen bir olay varsa ödeme yarıçapları
 * hesaplanır, rapor imzalanır ve FayPool sözleşmesine yazılır.
 */
import {
  CronCapability,
  HTTPClient,
  EVMClient,
  handler,
  ConsensusAggregationByFields,
  median,
  identical,
  Runner,
  getNetwork,
  encodeCallMsg,
  bytesToHex,
  hexToBase64,
  type HTTPSendRequester,
  type Runtime,
} from "@chainlink/cre-sdk"
import {
  encodeAbiParameters,
  parseAbiParameters,
  encodeFunctionData,
  decodeFunctionResult,
  keccak256,
  stringToHex,
  zeroAddress,
} from "viem"
import { FayPoolAbi } from "../contracts/abi/FayPool"
import { fetchAFAD, fetchEMSC, fetchUSGS, mergeStrongest, type QuakeEvent, type Region } from "./sources"
import { toFixedPoint, payoutRadiiKm } from "./intensity"

// ------------------------------------------------------------------ Config
type EvmConfig = {
  chainName: string
  fayPoolAddress: string // boş bırakılırsa zincire yazılmaz (sadece simülasyon logları)
  gasLimit: string
}

type DemoEvent = {
  timeIso: string
  lat: number
  lon: number
  depthKm: number
  mag: number
  place: string
}

type Config = {
  schedule: string
  region: Region
  minMagnitude: number
  lookbackMinutes: number
  minSources: number
  demoEvent?: DemoEvent | null
  evms: EvmConfig[]
  // çalışma anında eklenir
  nowMs?: number
}

// ------------------------------------------------------------------ Uzlaşı nesnesi
type ConsensusEvent = {
  eventKey: string // identical: node'lar aynı depremi seçmeli
  timeMs: number
  lat: number
  lon: number
  depthKm: number
  mag: number
  sourcesAgreed: number
  // kaynak başına dönen olay sayısı (video/log için; medyanla uzlaşır)
  nUSGS: number
  nEMSC: number
  nAFAD: number
}

const NO_EVENT: ConsensusEvent = {
  eventKey: "none",
  timeMs: 0,
  lat: 0,
  lon: 0,
  depthKm: 0,
  mag: 0,
  sourcesAgreed: 0,
  nUSGS: 0,
  nEMSC: 0,
  nAFAD: 0,
}

/** Zaman (dakika) + konum (0.1°) → aynı depremi tanımlayan kaba anahtar. */
function eventKeyOf(timeMs: number, lat: number, lon: number): string {
  const minute = Math.round(timeMs / 60_000)
  return `${minute}|${lat.toFixed(1)}|${lon.toFixed(1)}`
}

// ------------------------------------------------------------------ Node modunda çalışan kısım
const fetchStrongestQuake = (requester: HTTPSendRequester, config: Config): ConsensusEvent => {
  const nowMs = config.nowMs ?? Date.now()
  const sinceMs = nowMs - config.lookbackMinutes * 60_000

  if (config.demoEvent) {
    const d = config.demoEvent
    const timeMs = Date.parse(d.timeIso)
    return {
      eventKey: "demo|" + eventKeyOf(timeMs, d.lat, d.lon),
      timeMs,
      lat: d.lat,
      lon: d.lon,
      depthKm: d.depthKm,
      mag: d.mag,
      sourcesAgreed: 3,
      nUSGS: 1,
      nEMSC: 1,
      nAFAD: 1,
    }
  }

  const all: QuakeEvent[] = []
  const errors: string[] = []
  const counts: Record<string, number> = { USGS: 0, EMSC: 0, AFAD: 0 }
  const sources: Array<[string, () => QuakeEvent[]]> = [
    ["USGS", () => fetchUSGS(requester, config.region, sinceMs, nowMs, config.minMagnitude)],
    ["EMSC", () => fetchEMSC(requester, config.region, sinceMs, nowMs, config.minMagnitude)],
    ["AFAD", () => fetchAFAD(requester, config.region, sinceMs, nowMs, config.minMagnitude)],
  ]
  for (const [name, fn] of sources) {
    try {
      const evs = fn()
      counts[name] = evs.length
      all.push(...evs)
    } catch (e) {
      errors.push(`${name}: ${(e as Error).message}`)
    }
  }
  // En az minSources kaynak cevap vermediyse bu node güvenilir sonuç üretemez.
  const okSources = sources.length - errors.length
  if (okSources < config.minSources) {
    throw new Error(`Yeterli kaynak yok (${okSources}/${sources.length}): ${errors.join("; ")}`)
  }

  const merged = mergeStrongest(all, config.minSources)
  if (!merged || merged.mag < config.minMagnitude) {
    return { ...NO_EVENT, nUSGS: counts.USGS, nEMSC: counts.EMSC, nAFAD: counts.AFAD }
  }

  return {
    eventKey: eventKeyOf(merged.timeMs, merged.lat, merged.lon),
    timeMs: merged.timeMs,
    lat: merged.lat,
    lon: merged.lon,
    depthKm: merged.depthKm,
    mag: merged.mag,
    sourcesAgreed: merged.sourcesAgreed,
    nUSGS: counts.USGS,
    nEMSC: counts.EMSC,
    nAFAD: counts.AFAD,
  }
}

// ------------------------------------------------------------------ Zincir işlemleri
/** Son bloktan okur (finalized blok ~15 dk geride kalır; yeni deploy edilmiş sözleşme orada görünmez). */
function readActivePolicies(runtime: Runtime<Config>, evmClient: EVMClient, pool: string): bigint | null {
  try {
    const call = evmClient
      .callContract(runtime, {
        call: encodeCallMsg({
          from: zeroAddress,
          to: pool as `0x${string}`,
          data: encodeFunctionData({ abi: FayPoolAbi, functionName: "activePolicyCount" }),
        }),
      })
      .result()
    const hex = bytesToHex(call.data)
    if (!hex || hex === "0x") return null
    return decodeFunctionResult({ abi: FayPoolAbi, functionName: "activePolicyCount", data: hex }) as bigint
  } catch (e) {
    runtime.log(`activePolicyCount okunamadı (devam ediliyor): ${(e as Error).message}`)
    return null
  }
}

function writeQuakeReport(
  runtime: Runtime<Config>,
  evmClient: EVMClient,
  evm: EvmConfig,
  ev: ConsensusEvent
): string {
  const fp = toFixedPoint(ev)
  const eventId = keccak256(stringToHex(ev.eventKey))

  // FayPool.QuakeReport struct ile birebir aynı sıra ve tipler
  const payload = encodeAbiParameters(
    parseAbiParameters(
      "bytes32 eventId, uint64 eventTime, int32 latE6, int32 lonE6, uint32 magX100, " +
        "uint32 depthKmX10, uint32 fullRadiusKmX10, uint32 halfRadiusKmX10, uint32 cosLatE6, uint8 sourcesAgreed"
    ),
    [
      eventId,
      BigInt(Math.floor(ev.timeMs / 1000)),
      fp.latE6,
      fp.lonE6,
      fp.magX100,
      fp.depthKmX10,
      fp.fullRadiusKmX10,
      fp.halfRadiusKmX10,
      fp.cosLatE6,
      ev.sourcesAgreed,
    ]
  )

  // FayPool v2: tek kapı, (uint8 kind, bytes payload). kind 1 = deprem raporu
  const wrapped = encodeAbiParameters(parseAbiParameters("uint8 kind, bytes payload"), [1, payload])

  const report = runtime
    .report({
      encodedPayload: hexToBase64(wrapped),
      encoderName: "evm",
      signingAlgo: "ecdsa",
      hashingAlgo: "keccak256",
    })
    .result()

  const res = evmClient
    .writeReport(runtime, {
      receiver: evm.fayPoolAddress,
      report,
      gasConfig: { gasLimit: evm.gasLimit },
    })
    .result()

  const txHash = bytesToHex(res.txHash || new Uint8Array(32))
  runtime.log(`writeReport durumu: ${String(res.txStatus)} tx: ${txHash}`)
  if (res.errorMessage) runtime.log(`writeReport hata: ${res.errorMessage}`)
  return txHash
}

// ------------------------------------------------------------------ Tetikleyici
type Result = {
  triggered: boolean
  eventKey: string
  mag: number
  place?: string
  fullRadiusKm?: number
  halfRadiusKm?: number
  txHash?: string
}

const onCronTrigger = (runtime: Runtime<Config>): Result => {
  const cfg = runtime.config
  runtime.log(
    `quake-oracle: bölge [${cfg.region.minLat},${cfg.region.maxLat}]x[${cfg.region.minLon},${cfg.region.maxLon}] ` +
      `eşik M${cfg.minMagnitude}, son ${cfg.lookbackMinutes} dk, kaynak≥${cfg.minSources}` +
      (cfg.demoEvent ? " [DEMO OLAYI AKTİF]" : "")
  )

  const nowMs = runtime.now().getTime()

  // Her node bağımsız çeker; alanlar medyanla, eventKey identical ile uzlaşır.
  // SDK: alanlar çağrılmamış fabrika fonksiyonu olarak verilir (median / identical).
  const ev: ConsensusEvent = new HTTPClient()
    .sendRequest(
      runtime,
      fetchStrongestQuake,
      ConsensusAggregationByFields<ConsensusEvent>({
        eventKey: identical,
        timeMs: median,
        lat: median,
        lon: median,
        depthKm: median,
        mag: median,
        sourcesAgreed: median,
        nUSGS: median,
        nEMSC: median,
        nAFAD: median,
      }).withDefault(NO_EVENT)
    )({ ...cfg, nowMs })
    .result()

  runtime.log(`Kaynaklardan dönen olay sayısı → USGS: ${ev.nUSGS}, EMSC: ${ev.nEMSC}, AFAD: ${ev.nAFAD}`)
  if (ev.eventKey === "none" || ev.mag < cfg.minMagnitude) {
    runtime.log("Eşiği geçen deprem yok. Ödeme tetiklenmedi.")
    return { triggered: false, eventKey: "none", mag: 0 }
  }

  const radii = payoutRadiiKm(ev.mag)
  runtime.log(
    `UZLAŞILAN OLAY: M${ev.mag.toFixed(1)} @ ${ev.lat.toFixed(3)},${ev.lon.toFixed(3)} ` +
      `derinlik ${ev.depthKm.toFixed(0)} km, ${new Date(ev.timeMs).toISOString()}, ` +
      `${ev.sourcesAgreed} kaynak hemfikir. Ödeme yarıçapı: %100 ≤ ${radii.full.toFixed(0)} km, %50 ≤ ${radii.half.toFixed(0)} km`
  )

  const evm = cfg.evms[0]
  if (!evm || !evm.fayPoolAddress) {
    runtime.log("fayPoolAddress boş: zincire yazılmadı (sadece simülasyon).")
    return { triggered: true, eventKey: ev.eventKey, mag: ev.mag, fullRadiusKm: radii.full, halfRadiusKm: radii.half }
  }

  const network = getNetwork({ chainFamily: "evm", chainSelectorName: evm.chainName })
  if (!network) throw new Error(`Bilinmeyen zincir: ${evm.chainName}`)
  const evmClient = new EVMClient(network.chainSelector.selector)

  const active = readActivePolicies(runtime, evmClient, evm.fayPoolAddress)
  runtime.log(`FayPool aktif poliçe sayısı: ${active === null ? "okunamadı" : active}`)

  const txHash = writeQuakeReport(runtime, evmClient, evm, ev)
  return {
    triggered: true,
    eventKey: ev.eventKey,
    mag: ev.mag,
    fullRadiusKm: radii.full,
    halfRadiusKm: radii.half,
    txHash,
  }
}

const initWorkflow = (config: Config) => {
  const cron = new CronCapability()
  return [handler(cron.trigger({ schedule: config.schedule }), onCronTrigger)]
}

export async function main() {
  const runner = await Runner.newRunner<Config>()
  await runner.run(initWorkflow)
}
