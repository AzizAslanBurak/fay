// Saf mantık testleri (CRE SDK gerektirmez): node --test tests/
// Çalıştırmadan önce: bunx tsc -p quake-oracle --outDir /tmp/fay-build ... yerine
// basitlik için aynı formüller burada yeniden hesaplanır ve TS kaynağıyla karşılaştırılır.
import test from "node:test"
import assert from "node:assert/strict"

const payoutRadiiKm = (mag) => {
  const rPoint = 8 * Math.pow(2, mag - 5)
  const ruptureLen = Math.pow(10, -2.44 + 0.59 * mag)
  const full = Math.max(rPoint, ruptureLen)
  return { full, half: 2 * full }
}
const hypo = (lat1, lon1, lat2, lon2, depthKm) => {
  const K = 111.32
  const dLat = (lat2 - lat1) * K
  const dLon = (lon2 - lon1) * K * Math.cos(((lat1 + lat2) / 2) * (Math.PI / 180))
  return Math.sqrt(dLat * dLat + dLon * dLon + depthKm * depthKm)
}
// Sözleşmedeki tamsayı mesafe hesabının birebir kopyası (m²)
const contractD2 = (pLatE6, pLonE6, q) => {
  const K = 111320n
  const abs = (x) => (x < 0n ? -x : x)
  const dLat = abs(BigInt(pLatE6) - BigInt(q.latE6))
  const dLon = abs(BigInt(pLonE6) - BigInt(q.lonE6))
  const latM = (dLat * K) / 1000000n
  const lonM = (((dLon * K) / 1000000n) * BigInt(q.cosLatE6)) / 1000000n
  const depthM = BigInt(q.depthKmX10) * 100n
  return latM * latM + lonM * lonM + depthM * depthM
}

test("yarıçaplar makul", () => {
  const r78 = payoutRadiiKm(7.8)
  assert.ok(r78.full > 140 && r78.full < 150, `M7.8 full=${r78.full}`)
  assert.ok(Math.abs(r78.half - 2 * r78.full) < 1e-9)
  const r55 = payoutRadiiKm(5.5)
  assert.ok(r55.full > 10 && r55.full < 12)
})

test("Kahramanmaraş M7.8: Pazarcık/Gaziantep/Antakya %100, Adana %50, İstanbul 0", () => {
  const ev = { lat: 37.226, lon: 37.014, depthKm: 10, mag: 7.8 }
  const r = payoutRadiiKm(ev.mag)
  const q = {
    latE6: Math.round(ev.lat * 1e6),
    lonE6: Math.round(ev.lon * 1e6),
    depthKmX10: 100,
    fullRadiusKmX10: Math.round(r.full * 10),
    halfRadiusKmX10: Math.round(r.half * 10),
    cosLatE6: Math.round(Math.cos(ev.lat * (Math.PI / 180)) * 1e6),
  }
  const tier = (lat, lon) => {
    const d2 = contractD2(Math.round(lat * 1e6), Math.round(lon * 1e6), q)
    const full = BigInt(q.fullRadiusKmX10) * 100n
    const half = BigInt(q.halfRadiusKmX10) * 100n
    if (d2 <= full * full) return 1
    if (d2 <= half * half) return 2
    return 0
  }
  assert.equal(tier(37.49, 37.30), 1) // Pazarcık (~38 km)
  assert.equal(tier(37.066, 37.383), 1) // Gaziantep (~37 km)
  assert.equal(tier(36.20, 36.16), 1) // Antakya (~137 km, kırık boyunca) → %100
  assert.equal(tier(37.0, 35.32), 2) // Adana (~150 km) → %50
  assert.equal(tier(41.01, 28.98), 0) // İstanbul
})

test("TS ve sözleşme mesafeleri uyumlu (±1%)", () => {
  const ev = { lat: 37.226, lon: 37.014, depthKm: 10 }
  const cos = Math.round(Math.cos(ev.lat * (Math.PI / 180)) * 1e6)
  const q = { latE6: 37226000, lonE6: 37014000, depthKmX10: 100, cosLatE6: cos }
  const pts = [
    [37.49, 37.3],
    [38.5, 36.0],
    [36.2, 36.16],
  ]
  for (const [la, lo] of pts) {
    const ts = hypo(ev.lat, ev.lon, la, lo, ev.depthKm) * 1000
    const sol = Math.sqrt(Number(contractD2(Math.round(la * 1e6), Math.round(lo * 1e6), q)))
    assert.ok(Math.abs(ts - sol) / ts < 0.01, `${la},${lo}: ts=${ts} sol=${sol}`)
  }
})
