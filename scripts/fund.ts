/** Deploy edilmiş FayPool'u test cüzdanından fonlar: bun run scripts/fund.ts [miktarETH=0.03] */
import { readFileSync } from "node:fs"
import { resolve, dirname } from "node:path"
import { fileURLToPath } from "node:url"
import { createPublicClient, createWalletClient, http, formatEther, parseEther, encodeFunctionData, type Hex } from "viem"
import { privateKeyToAccount } from "viem/accounts"
import { sepolia } from "viem/chains"
import { FayPoolAbi } from "../contracts/abi/FayPool"

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..")
const RPC_URL = process.env.SEPOLIA_RPC_URL || "https://ethereum-sepolia-rpc.publicnode.com"
const amount = process.argv[2] || "0.03"
const dep = JSON.parse(readFileSync(resolve(ROOT, "deployments/sepolia.json"), "utf8"))
const env = Object.fromEntries(
  readFileSync(resolve(ROOT, ".env"), "utf8").split("\n")
    .map((l) => l.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/)).filter(Boolean).map((m) => [m![1], m![2]])
)
const account = privateKeyToAccount(("0x" + env.CRE_ETH_PRIVATE_KEY) as Hex)
const pub = createPublicClient({ chain: sepolia, transport: http(RPC_URL) })
const wallet = createWalletClient({ account, chain: sepolia, transport: http(RPC_URL) })

const bal = await pub.getBalance({ address: account.address })
console.log(`Cüzdan ${account.address}: ${formatEther(bal)} ETH`)
if (bal < parseEther(amount) + parseEther("0.002")) { console.log(`⛽ Yetersiz bakiye (${amount} ETH + gas gerekli).`); process.exit(2) }
console.log(`FayPool ${dep.fayPool} fonlanıyor: ${amount} ETH ...`)
const hash = await wallet.sendTransaction({ to: dep.fayPool, value: parseEther(amount), data: encodeFunctionData({ abi: FayPoolAbi, functionName: "fund" }) })
console.log(`tx: https://sepolia.etherscan.io/tx/${hash}`)
await pub.waitForTransactionReceipt({ hash })
console.log(`✅ Havuz bakiyesi: ${formatEther(await pub.getBalance({ address: dep.fayPool }))} ETH`)
