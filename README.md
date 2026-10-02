# Fay — Parametric Earthquake Insurance on Chainlink CRE

> Hasar tespiti yok. Üç bağımsız sismik kaynağın (USGS, EMSC, AFAD) Chainlink CRE üzerinde
> uzlaştığı deprem parametreleri, poliçe konumuna göre ödemeyi dakikalar içinde otomatik tetikler.

Tasarım: [`docs/DESIGN.md`](docs/DESIGN.md)

## Yapı

```
fay/
├── quake-oracle/          CRE workflow (TypeScript)
│   ├── main.ts            cron → 3 kaynak (node mode) → uzlaşı → rapor → FayPool
│   ├── sources.ts         USGS / EMSC / AFAD istemcileri + olay birleştirme
│   ├── intensity.ts       ödeme yarıçapları (R_full / R_half), sabit nokta dönüşümü
│   ├── config.staging.json   canlı veri
│   ├── config.demo.json      2023 Kahramanmaraş enjekte (video için)
│   └── workflow.yaml
├── contracts/
│   ├── FayPool.sol        poliçe, sermaye, CRE raporundan otomatik ödeme, devre kesici
│   ├── ReceiverTemplate.sol / IReceiver.sol / IERC165.sol   (Chainlink resmi şablon)
│   └── abi/FayPool.ts
├── tests/logic.test.mjs   yarıçap + mesafe matematiği (TS ↔ Solidity uyumu)
├── project.yaml           RPC hedefleri
└── KUR.command            tek tık: bun + cre CLI + login + simülasyon
```

## Chainlink servislerinin kullanıldığı dosyalar

| Dosya | Servis |
|---|---|
| `quake-oracle/main.ts` | CRE Cron Trigger, HTTP Capability (node mode), `ConsensusAggregationByFields` (median/identical), EVM Read (`callContract`), EVM Write (`runtime.report` + `writeReport`) |
| `quake-oracle/sources.ts` | CRE `HTTPSendRequester` |
| `contracts/FayPool.sol` | CRE `ReceiverTemplate` (Keystone Forwarder doğrulamalı `onReport`) |

## Hızlı başlangıç

```bash
./KUR.command                      # bun + cre CLI + login + bağımlılıklar + 2 simülasyon
cre workflow simulate quake-oracle --target demo-settings      # 2023 olayı, zincire yazmaz
cre workflow simulate quake-oracle --target staging-settings   # canlı veri
```

## Sepolia'da uçtan uca (faz 1)

1. `contracts/FayPool.sol`'u Remix'te derle; constructor'a **MockKeystoneForwarder** (Sepolia) `0x15fC6ae953E024d975e77382eEeC56A9101f9F88` ver, deploy et.
2. Havuzu fonla (`fund()` ile 0.05 ETH), bir poliçe al (`buyPolicy(37490000, 37300000, 1e16)` + prim).
3. `config.demo.json` → `fayPoolAddress` = sözleşme adresi; `.env` → test cüzdanı anahtarı.
4. `cre workflow simulate quake-oracle --target demo-settings --broadcast` → `PolicyPaid` eventi.

## Ödeme kuralı

`d` = hiposantr mesafesi. `R_full = max(8·2^(M−5), 10^(−2.44+0.59M))` km, `R_half = 2·R_full`.
`d ≤ R_full` → %100, `d ≤ R_half` → %50. Aynı olay iki kez işlenmez. Eşik M5.5, en az 2 kaynak.

> Prototiptir; parametrik eşikler aktüeryal olarak kalibre edilmeli, ürün sigorta mevzuatına tabidir.
