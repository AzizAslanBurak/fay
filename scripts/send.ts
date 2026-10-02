/** Test cüzdanından (.env) başka bir adrese Sepolia ETH gönderir: bun run scripts/send.ts <adres> <miktarETH> */
import { readFileSync } from "node:fs"
import { resolve, dirname } from "node:path"
import { fileURLToPath } from "node:url"
import { createPublicClient, createWalletClient, http, formatEther, parseEther, isAddress, type Hex } from "viem"
import { privateKeyToAccount } from "viem/accounts"
import { sepolia } from "viem/chains"

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..")
const RPC_URL = process.env.SEPOLIA_RPC_URL || "https://ethereum-sepolia-rpc.publicnode.com"

const [to, amount] = process.argv.slice(2)
if (!to || !isAddress(to) || !amount) {
  console.error("Kullanım: bun run scripts/send.ts <0x-adres> <miktarETH>")
  process.exit(1)
}
const env = Object.fromEntries(
  readFileSync(resolve(ROOT, ".env"), "utf8")
    .split("\n")
    .map((l) => l.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/))
    .filter(Boolean)
    .map((m) => [m![1], m![2]])
)
const account = privateKeyToAccount(("0x" + env.CRE_ETH_PRIVATE_KEY) as Hex)
const pub = createPublicClient({ chain: sepolia, transport: http(RPC_URL) })
const wallet = createWalletClient({ account, chain: sepolia, transport: http(RPC_URL) })

const bal = await pub.getBalance({ address: account.address })
console.log(`Gönderen ${account.address} bakiye ${formatEther(bal)} ETH → ${to} : ${amount} ETH`)
const hash = await wallet.sendTransaction({ to, value: parseEther(amount) })
console.log(`tx: https://sepolia.etherscan.io/tx/${hash}`)
await pub.waitForTransactionReceipt({ hash })
console.log(`✅ Gönderildi. Alıcı bakiyesi: ${formatEther(await pub.getBalance({ address: to }))} ETH`)
