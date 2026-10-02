# Fay — Parametric Earthquake Insurance on Chainlink CRE

> No claims, no adjusters. Three independent seismic feeds (USGS, EMSC, AFAD) reach consensus
> inside a Chainlink CRE workflow, and the signed report pays policyholders automatically — in minutes,
> not months. Private policies are settled inside a Confidential Workflow (TEE) so nobody, not even
> node operators, learns where you live.

[Türkçe README](docs/README.tr.md) · [Design doc](docs/DESIGN.md) · [Demo video script](docs/DEMO_SCRIPT.md)

**Live on Sepolia:** FayPool v3 [`0xdb12e1739c97a57c81e98af611c9d399485a378b`](https://sepolia.etherscan.io/address/0xdb12e1739c97a57c81e98af611c9d399485a378b)
(receives reports through Chainlink's `MockKeystoneForwarder` `0x15fC6ae953E024d975e77382eEeC56A9101f9F88`). Source verified — exact match on [Etherscan](https://sepolia.etherscan.io/address/0xdb12e1739c97a57c81e98af611c9d399485a378b#code) and [Sourcify](https://repo.sourcify.dev/11155111/0xdb12e1739c97a57c81e98af611c9d399485a378b).

## Why

After the 6 February 2023 Kahramanmaraş earthquakes, insurance payouts took months: loss adjustment is
slow, expensive and contested, and people get nothing in the 72 hours when cash matters most.
Parametric insurance fixes the *when*: pay on a measured event, not on a damage report. The hard part is
trust in the measurement — a single API can be wrong, late or manipulated. That is exactly what a
decentralised oracle network with built-in consensus is for.

## What Fay does

| Step | Where | What happens |
|---|---|---|
| 1. Buy cover | Flutter web app → `FayPool.buyPolicy` / `buyPolicyPrivate` | Pick a location on the map, choose coverage, pay a 5 % premium with MetaMask. Private policies store only `keccak256(lat, lon, salt)` on-chain. |
| 2. Watch | `quake-oracle` (CRE, cron every 5 min) | Every DON node independently reads USGS, EMSC and AFAD, filters by region and M ≥ 5.5, picks the strongest event. `ConsensusAggregationByFields` takes the median of magnitude/lat/lon/depth and requires an **identical** event key — if nodes disagree, no report is produced (no payout beats a wrong payout). |
| 3. Pay | Signed report → `KeystoneForwarder` → `FayPool.onReport` | The contract rejects replayed events, computes hypocentral distance to every public policy with integer math and pays 100 % inside `R_full`, 50 % inside `R_half`. |
| 4. Private claims | `claims-tee` (CRE Confidential Workflow) | Runs in an AWS Nitro enclave: fetches the Vault DON secret, pulls locations from the off-chain Policy Vault, verifies each commitment, computes tiers, and has the DON sign only `(policyId, tier)`. |
| 5. Stay solvent | `pool-guardian` (CRE, cron every 10 min) | Reads `reserveHealthBps`; below 100 % it writes a signed **pause** report, above 120 % a **resume** report. The circuit breaker is operated by the DON, not by a human key. |

Payout radius: `R_full = max(8·2^(M−5), 10^(−2.44+0.59·M))` km (second term = Wells & Coppersmith 1994
rupture length, so large quakes pay along the fault), `R_half = 2·R_full`. M7.8 → 145 / 290 km.

## Chainlink services used

| File | Service |
|---|---|
| `quake-oracle/main.ts` | CRE Cron Trigger · HTTP capability in node mode · `ConsensusAggregationByFields` (median / identical) · EVM Read (`callContract`) · EVM Write (`runtime.report` + `writeReport`) |
| `quake-oracle/sources.ts` | CRE `HTTPSendRequester` (USGS, EMSC, AFAD clients) |
| `pool-guardian/main.ts` | CRE Cron Trigger · EVM Read · EVM Write (signed pause/resume reports) |
| `claims-tee/main.ts` | CRE **Confidential Workflows** (`handlerInTee`, `TeeRuntime`, AWS Nitro) · Vault DON secret via `getSecret` inside the enclave · HTTP from the enclave · `usingTheDons()` → signed report → EVM Write |
| `secrets.yaml` | Vault DON secret mapping (`VAULT_API_KEY`) |
| `contracts/FayPool.sol` | Chainlink `ReceiverTemplate` / `IReceiver` (Forwarder-verified `onReport`), one entry point multiplexing three report kinds |

## On-chain proof (Sepolia, FayPool v3)

| Demo | Tx |
|---|---|
| 2023 Kahramanmaraş M7.8 report → policy #1 (Pazarcık) paid 100 % | [`0xb126d3c4…25ea`](https://sepolia.etherscan.io/tx/0xb126d3c4f55552eb3c80aa61944b7c30322242069a52fa1ec85d5db3246225ea) |
| Guardian: reserve < 100 % → sales **paused** | [`0x6a7f288f…4f62`](https://sepolia.etherscan.io/tx/0x6a7f288ffb34d68612923cd8d7036f62abe1e441f9af62d0c204644196ef4f62) |
| Guardian: reserve ≥ 120 % → sales **resumed** | [`0x15d3e8d3…055d`](https://sepolia.etherscan.io/tx/0x15d3e8d3c4d0321f42b05f92e80155015914dcd3b7d91be79d8d46d7cb2d055d) |
| Confidential claims (TEE) → private policy #2 (Antakya) tier 1, location never revealed (paid 0.0012 ETH = the pool's remaining capital; `_pay` caps at balance) | [`0x1262467d…2587`](https://sepolia.etherscan.io/tx/0x1262467d6067c33c8e78cfdfe64418d37ab665ddc2b37c77fec7bc75be8b2587) |

## Repository layout

```
fay/
├── quake-oracle/     CRE workflow: 3 seismic feeds → consensus → quake report
│   ├── main.ts · sources.ts · intensity.ts
│   └── config.{staging,demo,production}.json · workflow.yaml
├── pool-guardian/    CRE workflow: reserve health → pause / resume reports
├── claims-tee/       CRE Confidential Workflow: private policies settled in an enclave
├── vault/            Policy Vault (Bun): off-chain private locations, API-key protected
├── contracts/        FayPool.sol + Chainlink ReceiverTemplate / IReceiver / IERC165, abi/
├── app/              Flutter Web dApp (MetaMask, OpenStreetMap, EN/TR)
├── scripts/          deploy.ts (solc-js + viem, idempotent) · verify.ts · send.ts
├── tests/            radius & distance maths, TS ↔ Solidity parity
├── docs/             DESIGN.md · DEMO_SCRIPT.md · README.tr.md
├── secrets.yaml · project.yaml · .env.example
└── *.command         one-click macOS runners (KUR, DEPLOY, APP, VAULT, VERIFY, GIT, …)
```

## Run it

```bash
# 0. prerequisites: bun, cre CLI (KUR.command installs both and logs you in)
./KUR.command

# simulate the oracle with live data / with the injected 2023 event (no chain write)
cre workflow simulate quake-oracle --target staging-settings --non-interactive --trigger-index 0
cre workflow simulate quake-oracle --target demo-settings    --non-interactive --trigger-index 0

# deploy FayPool to Sepolia, fund it, buy a public + a private policy, run all 4 on-chain demos
./DEPLOY.command            # needs CRE_ETH_PRIVATE_KEY (test wallet) in .env, ~0.01 Sepolia ETH

# dApp (http://localhost:8080) + Policy Vault (http://localhost:8787) for private policies
./VAULT.command && ./APP.command

# verify FayPool source on Sourcify (and Etherscan if ETHERSCAN_API_KEY is set in .env)
./VERIFY.command

# maths tests
node --test tests/logic.test.mjs
```

Manual equivalents of the on-chain demos:

```bash
cre workflow simulate quake-oracle  --target demo-settings   --non-interactive --trigger-index 0 --broadcast
cre workflow simulate pool-guardian --target demo-settings   --non-interactive --trigger-index 0 --broadcast   # pause
cre workflow simulate pool-guardian --target resume-settings --non-interactive --trigger-index 0 --broadcast   # resume
cre workflow simulate claims-tee    --target staging-settings --non-interactive --trigger-index 0 --broadcast  # TEE claims
```

## Privacy model

A private policy writes only `keccak256(abi.encode(int32 latE6, int32 lonE6, bytes32 salt))` to the chain.
The plaintext location lives in the Policy Vault behind an API key. After a qualifying quake, `claims-tee`
runs under `handlerInTee`: only the enclave receives the Vault DON secret, fetches the locations, checks every
commitment against the on-chain hash, computes distance and tier, and the DON signs just the `(policyId, tier)`
list. Neither the chain nor the node operators ever see the coordinates. (The CRE simulator emulates the
enclave; production Confidential Workflows are in private beta.)

## Security notes

- Reports are accepted only from the Keystone Forwarder (`ReceiverTemplate`), and each `eventId` is processed once.
- Consensus is fail-closed: an identical-key mismatch across nodes yields `NO_EVENT`, never a partial payout.
- All geometry is integer fixed-point and identical in TypeScript and Solidity (`tests/logic.test.mjs`); `cos(lat)`
  and the radii are computed off-chain and carried in the signed report, so the contract only compares.
- The guardian rejects stale observations (`observedAt` older than the last one).

## Limitations / next steps

Prototype on Sepolia with ETH as the unit of account. Production would need a stablecoin pool, actuarially
calibrated radii and thresholds, pagination for large policy sets, Chainlink ACE for eligibility/KYC at
purchase, CCIP for multi-chain capital, and of course a licensed insurance carrier. Not a licensed insurance
product.

## License

MIT
