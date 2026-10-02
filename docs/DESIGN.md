# Fay — Deprem için Parametrik Sigorta (Chainlink CRE)

> Tek sayfalık tasarım. Hedef: Chainlink hackathon'u, "Risk & Compliance" (birincil) / "DeFi & Tokenization" (ikincil) kategorileri.

## 1. Sorun

Depremden sonra sigorta ödemesi aylar sürer: hasar tespiti pahalı, tartışmalı ve yavaş. İnsanların paraya en çok ihtiyaç duyduğu ilk 72 saatte eline hiçbir şey geçmez. 2023 Kahramanmaraş depremi bunu milyonlarca kişiye yaşattı.

## 2. Çözüm (tek cümle)

Hasar tespiti yok: bağımsız üç sismik kaynağın (USGS, EMSC, AFAD) **CRE üzerinde uzlaştığı** deprem parametreleri, poliçe konumuna göre otomatik ödemeyi dakikalar içinde tetikler.

## 3. Akış

```
 Kullanıcı (Flutter)            Chainlink CRE (DON)                     Ethereum (Sepolia)
 ─────────────────             ───────────────────────────             ──────────────────
 konum + teminat seç ─────────────────────────────────────────────▶  FayPool.buyPolicy()
                                                                      (prim öder, poliçe açılır)

                               ┌ Cron (her 5 dk) ───────────────┐
                               │ her node bağımsız olarak:      │
                               │   USGS  ─┐                     │
                               │   EMSC  ─┼─▶ en güçlü olayı seç│
                               │   AFAD  ─┘   (bölge + eşik)    │
                               │ ConsensusAggregationByFields:  │
                               │   mag/lat/lon/time → medyan    │
                               │   eventKey → identical         │
                               │ yarıçapları hesapla (R_full,   │
                               │   R_half), rapor imzala        │
                               └────────────┬───────────────────┘
                                            │ writeReport (ecdsa, keccak256)
                                            ▼
                                                                  FayPool.onReport()
                                                                   ├ eventId tekrarı reddet
                                                                   ├ her aktif poliçe için mesafe
                                                                   ├ ≤R_full → %100, ≤R_half → %50
                                                                   └ ödeme cüzdana (push)
```

## 4. Chainlink ürünleri ve rolleri

| Ürün | Nerede | Neden kritik |
|---|---|---|
| **CRE – HTTP + runInNodeMode + Consensus** | `quake-oracle/main.ts` | Tek kaynak manipüle edilebilir; üç kaynağın medyanı edilemez. Ürünün özü bu. |
| **CRE – EVM Write (signed report)** | `writeReport` → `FayPool.onReport` | Ödeme kararını imzalı rapor taşır; sözleşme sadece Forwarder'dan gelen raporu kabul eder. |
| **CRE – EVM Read + Write (`pool-guardian`)** | `pool-guardian/main.ts` | Her 10 dk havuz sağlığını okur; <%100 → imzalı "durdur", ≥%120 → "aç" raporu. Devre kesiciyi insan değil DON yönetir. |
| **Confidential Workflows (TEE) + Vault DON secrets** | `claims-tee/main.ts` | Gizli poliçenin konumu zincirde yok (keccak taahhüdü). Enclave API anahtarını alır, Policy Vault'tan konumu çeker, taahhüdü doğrular, kademeyi hesaplar; DON'a yalnızca (id, kademe) listesi çıkar. Node operatörleri konumu görmez. |
| **ACE** (faz 2) | poliçe alımı | Uygunluk/KYC politikası. |
| **CCIP** (faz 3) | havuz sermayesi | Birden fazla zincirden sermaye toplama. |

## 5. Ödeme kuralı (parametrik)

- Tetik eşiği: `M ≥ 5.5` (config).
- Hiposantr mesafesi `d = sqrt(yüzey_mesafesi² + derinlik²)` km.
- `R_full(M) = max( 8 · 2^(M−5) , 10^(−2.44 + 0.59·M) )` km — ikinci terim Wells & Coppersmith (1994) yüzey kırık uzunluğu; büyük depremlerde hasar fay boyunca yayılır (2023: ~300 km). `R_half = 2 · R_full`. Örn. M7.8 → 145 / 290 km; M6.0 → 16 / 32 km. Test: Antakya (137 km) %100, Adana (150 km) %50, İstanbul 0.
- `d ≤ R_full` → teminatın %100'ü, `d ≤ R_half` → %50'si, aksi halde 0.
- Aynı `eventId` (zaman+konum anahtarı) ikinci kez işlenmez (replay koruması).
- Yarıçaplar ve `cos(lat)` CRE tarafında hesaplanır, sözleşme sadece karşılaştırır (zincirde `log/pow/cos` yok).

> Not: Yarıçap formülü kalibre edilmemiş bir yaklaşımdır; sunumda "parametrik eşikler aktüeryal olarak kalibre edilmelidir" denecek. Hackathon için şeffaf ve tutarlı olması yeterli.

## 6. Uzlaşı tasarımı

Her node üç kaynaktan bağımsız okur, bölge filtresi (Türkiye kutusu) ve eşik uygular, en güçlü olayı seçer ve şu nesneyi döner:

```ts
{ eventKey: string,  // "YYYYMMDDHHmm|lat0.1|lon0.1" — identical
  timeMs: number,    // median
  lat: number, lon: number, depthKm: number, mag: number,  // median
  sourcesAgreed: number }  // median
```

`eventKey` identical olduğu için node'lar farklı depremleri seçerse uzlaşı başarısız olur ve `withDefault(NO_EVENT)` ile güvenli tarafta kalınır: **yanlış ödeme yerine ödeme yapmama** tercih edilir.

## 7. Demo senaryosu (video, 3 dk)

1. Flutter'da İstanbul/Hatay için poliçe al (Sepolia).
2. `config.demo.json` ile 2023-02-06 Kahramanmaraş (M7.8, 37.226N 37.014E, 10 km) olayını enjekte et.
3. `cre workflow simulate` loglarında üç kaynağın okunup medyanda uzlaştığını göster.
4. `--broadcast` ile raporun Sepolia'ya yazılması, `PolicyPaid` eventi, cüzdana düşen ödeme.
5. Havuz sağlık göstergesi (teminat/sermaye) ve devre kesici.

## 8. Yol haritası

| Faz | Çıktı | Durum |
|---|---|---|
| 0 | Tasarım, CRE kurulumu, `quake-oracle` simülasyonda çalışıyor | ✅ |
| 1 | `FayPool.sol` Sepolia'da, `--broadcast` ile uçtan uca ödeme | ✅ tx `0x8e3fc7…` (v1), `0xbbb02c…` (v2) |
| 2 | Flutter Web uygulaması (poliçe al, panel, poliçelerim, EN/TR) | ✅ |
| 3a | `pool-guardian` workflow'u + devre kesici (FayPool v2, iki tür rapor) | ✅ tx `0xbfc2fd…` (pause), `0x471b45…` (resume) |
| 3b | Gizli poliçe: zincirde sadece taahhüt; `claims-tee` (handlerInTee, AWS Nitro) + Policy Vault | ✅ tx `0x126246…` (FayPool v3) |
| 4 | Video senaryosu ✅ (`docs/DEMO_SCRIPT.md`), README (EN) ✅, kaynak doğrulama ✅ Etherscan + Sourcify exact match (`VERIFY.command`), video kaydı ⏳; (opsiyonel) ACE/CCIP | |

## 9. Riskler

- AFAD endpoint'i 302 ile `servisnet.afad.gov.tr`'ye yönlendiriyor; doğrudan o adres kullanılıyor.
- EMSC `maxradius` derece cinsinden; kutu filtresi kullanıyoruz.
- Sözleşmedeki poliçe döngüsü gas sınırlıdır (MVP); üretimde sayfalama gerekir.
- Parametrik sigorta düzenlemeye tabidir; prototip olduğu açıkça belirtilecek.
