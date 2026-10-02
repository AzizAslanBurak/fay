/**
 * Fay – pool-guardian CRE workflow (devre kesici)
 * -----------------------------------------------
 * Her 10 dakikada FayPool'un ödeme gücünü okur:
 *   health = kasa / (aktif teminat × rezerv oranı)   (1e4 = %100)
 * health < pauseBelowBps  ve satış açıksa  → imzalı "durdur" raporu yazar
 * health ≥ resumeAboveBps ve satış kapalıysa → imzalı "aç" raporu yazar (histerezis)
 * Aksi halde sadece loglar. Karar bir insana değil, DON uzlaşısına bağlıdır.
 */
import {
  CronCapability,
  EVMClient,
  handler,
  Runner,
  getNetwork,
  encodeCallMsg,
  bytesToHex,
  hexToBase64,
  type Runtime,
} from "@chainlink/cre-sdk"
import { encodeAbiParameters, parseAbiParameters, encodeFunctionData, decodeFunctionResult, zeroAddress } from "viem"
import { FayPoolAbi } from "../contracts/abi/FayPool"

type EvmConfig = { chainName: string; fayPoolAddress: string; gasLimit: string }
type Config = {
  schedule: string
  pauseBelowBps: number // örn. 10000 (%100)
  resumeAboveBps: number // örn. 12000 (%120) – flip-flop'u önler
  demoAction?: "pause" | "resume" | null // video için: ne olursa olsun bu raporu yaz
  evms: EvmConfig[]
}

type Result = { healthBps: string; salesPaused: boolean; action: "none" | "pause" | "resume"; txHash?: string }

function readUint(runtime: Runtime<Config>, evm: EVMClient, pool: `0x${string}`, fn: "reserveHealthBps" | "salesPaused" | "totalActiveCoverage" | "activePolicyCount") {
  const call = evm
    .callContract(runtime, {
      call: encodeCallMsg({ from: zeroAddress, to: pool, data: encodeFunctionData({ abi: FayPoolAbi, functionName: fn }) }),
    })
    .result()
  return decodeFunctionResult({ abi: FayPoolAbi, functionName: fn, data: bytesToHex(call.data) })
}

const onCronTrigger = (runtime: Runtime<Config>): Result => {
  const cfg = runtime.config
  const evmCfg = cfg.evms[0]
  const network = getNetwork({ chainFamily: "evm", chainSelectorName: evmCfg.chainName })
  if (!network) throw new Error(`Bilinmeyen zincir: ${evmCfg.chainName}`)
  const evm = new EVMClient(network.chainSelector.selector)
  const pool = evmCfg.fayPoolAddress as `0x${string}`

  // Zincir okumaları (DON uzlaşısıyla)
  const healthBps = readUint(runtime, evm, pool, "reserveHealthBps") as bigint
  const salesPaused = readUint(runtime, evm, pool, "salesPaused") as boolean
  const activeCoverage = readUint(runtime, evm, pool, "totalActiveCoverage") as bigint
  const activePolicies = readUint(runtime, evm, pool, "activePolicyCount") as bigint

  const MAX = (1n << 256n) - 1n
  const healthStr = healthBps === MAX ? "∞ (aktif teminat yok)" : `${Number(healthBps) / 100}%`
  runtime.log(
    `pool-guardian: sağlık ${healthStr} | satış ${salesPaused ? "DURDURULMUŞ" : "açık"} | ` +
      `aktif teminat ${activeCoverage} wei | aktif poliçe ${activePolicies}` +
      (cfg.demoAction ? ` [DEMO: ${cfg.demoAction}]` : "")
  )

  let action: Result["action"] = "none"
  if (cfg.demoAction === "pause") action = "pause"
  else if (cfg.demoAction === "resume") action = "resume"
  else if (!salesPaused && healthBps < BigInt(cfg.pauseBelowBps)) action = "pause"
  else if (salesPaused && healthBps >= BigInt(cfg.resumeAboveBps)) action = "resume"

  if (action === "none") {
    runtime.log("Müdahale gerekmiyor.")
    return { healthBps: healthBps.toString(), salesPaused, action }
  }

  runtime.log(action === "pause" ? "⚠️ Rezerv yetersiz → satışlar DURDURULUYOR" : "✅ Rezerv toparlandı → satışlar AÇILIYOR")

  // FayPool.GuardianReport ile birebir: (uint64 observedAt, uint256 healthBps, bool pause)
  const observedAt = BigInt(Math.floor(runtime.now().getTime() / 1000))
  const payload = encodeAbiParameters(parseAbiParameters("uint64 observedAt, uint256 healthBps, bool pause"), [
    observedAt,
    healthBps === MAX ? 0n : healthBps,
    action === "pause",
  ])
  const wrapped = encodeAbiParameters(parseAbiParameters("uint8 kind, bytes payload"), [2, payload])

  const report = runtime
    .report({ encodedPayload: hexToBase64(wrapped), encoderName: "evm", signingAlgo: "ecdsa", hashingAlgo: "keccak256" })
    .result()
  const res = evm.writeReport(runtime, { receiver: evmCfg.fayPoolAddress, report, gasConfig: { gasLimit: evmCfg.gasLimit } }).result()
  const txHash = bytesToHex(res.txHash || new Uint8Array(32))
  runtime.log(`writeReport durumu: ${String(res.txStatus)} tx: ${txHash}`)
  if (res.errorMessage) runtime.log(`writeReport hata: ${res.errorMessage}`)
  return { healthBps: healthBps.toString(), salesPaused, action, txHash }
}

const initWorkflow = (config: Config) => {
  const cron = new CronCapability()
  return [handler(cron.trigger({ schedule: config.schedule }), onCronTrigger)]
}

export async function main() {
  const runner = await Runner.newRunner<Config>()
  await runner.run(initWorkflow)
}
