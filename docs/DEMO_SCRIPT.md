# Fay — 3-minute demo video script

Target: 2:50–3:00. Screen recording (QuickTime / OBS) at 1080p, voice-over in English (Turkish
text is for you — read either; add the other as subtitles if you like). Everything shown is real:
the simulator logs, the Sepolia transactions and the dApp.

## Preparation (before recording)

1. `./VAULT.command` and `./APP.command` running; browser at `http://localhost:8080`, MetaMask on Sepolia
   with ≥ 0.005 ETH, language set to EN.
2. Three Terminal tabs ready, in `~/Projects/fay`:
   - **T1:** `cre workflow simulate quake-oracle --target staging-settings --non-interactive --trigger-index 0`
   - **T2:** `cre workflow simulate quake-oracle --target demo-settings --non-interactive --trigger-index 0 --broadcast`
   - **T3:** `cre workflow simulate claims-tee --target staging-settings --non-interactive --trigger-index 0`
   (Run T1 once beforehand so the output is already visible; T2 and T3 are typed but not yet executed.)
3. Browser tabs: FayPool on Etherscan (`#code` after verification), the four demo transactions from the README.
4. If the pool was drained by a previous demo, re-run `./DEPLOY.command` (or `./TOPUP.command` + `fund`) so the
   payout actually lands on camera. Note the policy you will buy must be near Kahramanmaraş (use the "Hatay" or
   "Kahramanmaraş" preset) so the injected 2023 event pays it.

---

## 0:00 – 0:25 · The problem  (slide or the dashboard "How it works" card)

**EN:** "On 6 February 2023 two earthquakes hit south-east Türkiye. Insurance payouts took months —
loss adjusters, disputes, paperwork — while people needed cash in the first 72 hours.
Fay is parametric earthquake insurance: no claims, no adjusters. If a measured quake hits your
payout radius, you get paid automatically, in minutes."

**TR:** 6 Şubat 2023'te sigorta ödemeleri aylar sürdü. Fay parametrik deprem sigortası: hasar tespiti yok;
ölçülen deprem ödeme yarıçapına girerse ödeme dakikalar içinde otomatik.

## 0:25 – 0:55 · Buy a policy  (dApp → "Get covered")

Click the **Kahramanmaraş** preset, set coverage with the slider, show the premium (5 %), keep
**Private policy** ON, click **Buy policy**, confirm in MetaMask, show the green "Policy purchased!".

**EN:** "The user picks a location and coverage and pays a five-percent premium. With a private policy the
chain only stores a hash commitment of the coordinates — the location itself goes to an off-chain Policy Vault.
Nobody can read where you live from the blockchain."

**TR:** Konum + teminat, %5 prim. Gizli poliçede zincire sadece koordinatların hash taahhüdü yazılır.

## 0:55 – 1:40 · The oracle: three feeds, one consensus  (T1 output, then T2)

Scroll T1 so the lines with `USGS`, `EMSC`, `AFAD` counts and the `ConsensusAggregationByFields` result are visible.
Then run **T2** (demo target, `--broadcast`) and wait for `writeReport durumu: 2` / tx hash.

**EN:** "This is the Chainlink CRE workflow. Every node of the DON independently calls USGS, EMSC and
Turkey's AFAD, filters for magnitude 5.5 and above in the region, and picks the strongest event.
CRE's consensus aggregation takes the median of magnitude, location and depth, and requires an
*identical* event key across nodes — if the nodes disagree, no report is produced. A missing payout is
safer than a wrong one.
For the demo I inject the real 2023 M7.8 Pazarcık event. The workflow computes the payout radii —
145 km full, 290 km half, following Wells & Coppersmith rupture length — signs the report, and
writes it on-chain through the Keystone Forwarder."

**TR:** Her node üç kaynağı bağımsız okur; medyan + identical eventKey ile uzlaşı; uzlaşmazsa rapor yok.
2023 M7.8 olayı enjekte edilir, yarıçaplar hesaplanır, imzalı rapor Forwarder üzerinden zincire yazılır.

## 1:40 – 2:05 · The payout  (Etherscan tx → dApp "My policies")

Open the T2 transaction on Etherscan: `ReportProcessed`, internal transfer to the holder.
Switch to the dApp: dashboard shows the processed quake, "My policies" shows the policy as **Paid out**.

**EN:** "The contract only accepts reports from the Forwarder, rejects replayed events, computes the
hypocentral distance to every policy with integer math — the same math as the TypeScript side, tested
for parity — and pays 100 % inside the full radius, 50 % inside the half radius. Here is the ETH arriving
in the wallet, and the policy flipping to *paid out* in the app."

## 2:05 – 2:35 · Confidential claims + the guardian  (T3, then Etherscan)

Run **T3** (claims-tee). Point at `handlerInTee`, `getSecret`, the vault call and the final `paidTiers`.
Show the TEE transaction and the pause / resume guardian transactions from the README.

**EN:** "Private policies are settled by a Confidential Workflow. Inside an AWS Nitro enclave the workflow
pulls the Vault DON secret, fetches the locations from the Policy Vault, verifies each commitment against
the on-chain hash, computes the tier, and the DON signs only policy-id and tier. The coordinates never leave
the enclave — not to the chain, not to the node operators.
A second workflow, the pool guardian, reads reserve health every ten minutes and writes a signed pause
report below 100 % and a resume report above 120 %. The circuit breaker is operated by the DON, not by an
admin key. All four flows are live on Sepolia."

**TR:** Gizli poliçeler enclave'de çözülür, sadece (id, kademe) imzalanır. Bekçi workflow'u devre kesiciyi
DON imzasıyla yönetir. Dört akış da Sepolia'da canlı.

## 2:35 – 2:55 · Why Chainlink, what's next  (repo README on screen)

**EN:** "Fay uses CRE cron, HTTP in node mode with field-level consensus, EVM read and write with signed
reports, Confidential Workflows with Vault DON secrets, and the official ReceiverTemplate. Next: a stablecoin
pool, ACE for eligibility at purchase, CCIP to pool capital across chains, and actuarial calibration of the
radii. Code, design doc and every transaction are in the repo. Thank you."

---

## Checklist before upload

- [ ] Contract verified (`./VERIFY.command`) so Etherscan shows source.
- [ ] README transactions open and succeed (status Success).
- [ ] Video ≤ 3:00, 1080p, audio audible; no `.env`, private keys or seed phrases on screen (hide the `.env` tab, blur MetaMask account menu).
- [ ] Repo public, latest commit pushed (`./GIT.command`).
