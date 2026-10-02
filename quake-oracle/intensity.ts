/**
 * Parametrik ödeme yarıçapları. Sözleşmede log/pow/cos olmadığı için
 * bu değerler CRE'de hesaplanıp imzalı raporla zincire taşınır.
 *
 * Küçük/orta depremlerde hasar episantr çevresinde yoğunlaşır; büyük depremlerde
 * ise fay kırığı boyunca yüzlerce km'ye yayılır (2023 Kahramanmaraş: ~300 km).
 * Bu yüzden iki ölçeğin büyüğü alınır:
 *   R_point(M) = 8 · 2^(M−5) km                      (nokta kaynak yaklaşımı)
 *   L_WC(M)    = 10^(−2.44 + 0.59·M) km              (Wells & Coppersmith 1994, yüzey kırık uzunluğu)
 *   R_full = max(R_point, L_WC)  → %100 ödeme
 *   R_half = 2 · R_full          → %50 ödeme
 *
 * Örnek: M7.8 → 145 / 290 km ; M7.0 → 32 / 65 km ; M6.0 → 16 / 32 km ; M5.5 → 11 / 23 km
 * NOT: Kalibre edilmemiş yaklaşımdır; üretimde aktüeryal model gerekir.
 */
export function payoutRadiiKm(mag: number): { full: number; half: number } {
  const rPoint = 8 * Math.pow(2, mag - 5)
  const ruptureLen = Math.pow(10, -2.44 + 0.59 * mag)
  const full = Math.max(rPoint, ruptureLen)
  return { full, half: 2 * full }
}

/** Hiposantr mesafesi (km): yüzey mesafesi (equirectangular) + derinlik. */
export function hypocentralDistanceKm(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number,
  depthKm: number
): number {
  const KM_PER_DEG = 111.32
  const dLat = (lat2 - lat1) * KM_PER_DEG
  const dLon = (lon2 - lon1) * KM_PER_DEG * Math.cos(((lat1 + lat2) / 2) * (Math.PI / 180))
  return Math.sqrt(dLat * dLat + dLon * dLon + depthKm * depthKm)
}

/** Sözleşmeye gönderilecek sabit noktalı alanlar. */
export function toFixedPoint(ev: { lat: number; lon: number; depthKm: number; mag: number }) {
  const r = payoutRadiiKm(ev.mag)
  return {
    latE6: Math.round(ev.lat * 1e6),
    lonE6: Math.round(ev.lon * 1e6),
    magX100: Math.round(ev.mag * 100),
    depthKmX10: Math.round(ev.depthKm * 10),
    fullRadiusKmX10: Math.round(r.full * 10),
    halfRadiusKmX10: Math.round(r.half * 10),
    cosLatE6: Math.round(Math.cos(ev.lat * (Math.PI / 180)) * 1e6),
  }
}
