/**
 * Üç bağımsız sismik kaynaktan deprem olaylarını çekip ortak bir forma getirir.
 * Bu dosya CRE'nin "node mode" içinde çalışır: her DON node'u bu fonksiyonları
 * kendi başına çalıştırır, sonuçlar daha sonra uzlaşıyla birleştirilir.
 */
import type { HTTPSendRequester } from "@chainlink/cre-sdk"

export type QuakeEvent = {
  source: "USGS" | "EMSC" | "AFAD"
  id: string
  timeMs: number
  lat: number
  lon: number
  depthKm: number
  mag: number
  place: string
}

export type Region = {
  minLat: number
  maxLat: number
  minLon: number
  maxLon: number
}

const dec = new TextDecoder()

function getJson(requester: HTTPSendRequester, url: string): unknown {
  const resp = requester.sendRequest({ url, method: "GET" as const }).result()
  if (resp.statusCode !== 200) {
    throw new Error(`HTTP ${resp.statusCode} from ${url}`)
  }
  return JSON.parse(dec.decode(resp.body))
}

function isoNoMs(d: Date): string {
  return d.toISOString().replace(/\.\d{3}Z$/, "")
}

// ---------------------------------------------------------------- USGS
// GeoJSON: properties.mag, properties.time (epoch ms), geometry.coordinates [lon, lat, depth]
export function fetchUSGS(
  requester: HTTPSendRequester,
  region: Region,
  sinceMs: number,
  untilMs: number,
  minMag: number
): QuakeEvent[] {
  const url =
    "https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson" +
    `&starttime=${isoNoMs(new Date(sinceMs))}&endtime=${isoNoMs(new Date(untilMs))}` +
    `&minmagnitude=${minMag}` +
    `&minlatitude=${region.minLat}&maxlatitude=${region.maxLat}` +
    `&minlongitude=${region.minLon}&maxlongitude=${region.maxLon}` +
    "&orderby=magnitude&limit=20"
  const data = getJson(requester, url) as {
    features?: Array<{
      id: string
      properties: { mag: number | null; time: number; place: string | null }
      geometry: { coordinates: [number, number, number] }
    }>
  }
  return (data.features ?? [])
    .filter((f) => f.properties.mag !== null)
    .map((f) => ({
      source: "USGS" as const,
      id: f.id,
      timeMs: f.properties.time,
      lon: f.geometry.coordinates[0],
      lat: f.geometry.coordinates[1],
      depthKm: Math.abs(f.geometry.coordinates[2] ?? 10),
      mag: f.properties.mag as number,
      place: f.properties.place ?? "",
    }))
}

// ---------------------------------------------------------------- EMSC
// GeoJSON: properties.mag, properties.time (ISO), properties.lat/lon/depth, flynn_region
export function fetchEMSC(
  requester: HTTPSendRequester,
  region: Region,
  sinceMs: number,
  untilMs: number,
  minMag: number
): QuakeEvent[] {
  const url =
    "https://www.seismicportal.eu/fdsnws/event/1/query?format=json" +
    `&start=${isoNoMs(new Date(sinceMs))}&end=${isoNoMs(new Date(untilMs))}` +
    `&minmag=${minMag}` +
    `&minlat=${region.minLat}&maxlat=${region.maxLat}` +
    `&minlon=${region.minLon}&maxlon=${region.maxLon}` +
    "&orderby=magnitude&limit=20"
  const data = getJson(requester, url) as {
    features?: Array<{
      id: string
      properties: {
        mag: number
        time: string
        lat: number
        lon: number
        depth: number
        flynn_region?: string
      }
    }>
  }
  return (data.features ?? []).map((f) => ({
    source: "EMSC" as const,
    id: f.id,
    timeMs: Date.parse(f.properties.time),
    lat: f.properties.lat,
    lon: f.properties.lon,
    depthKm: Math.abs(f.properties.depth ?? 10),
    mag: f.properties.mag,
    place: f.properties.flynn_region ?? "",
  }))
}

// ---------------------------------------------------------------- AFAD
// Düz JSON dizisi; tüm sayısal alanlar string. `date` Türkiye yerel saati (UTC+3), zone bilgisi yok.
// deprem.afad.gov.tr 302 ile servisnet'e yönlendirdiği için doğrudan servisnet kullanılır.
const AFAD_TZ_OFFSET_MS = 3 * 60 * 60 * 1000

export function fetchAFAD(
  requester: HTTPSendRequester,
  region: Region,
  sinceMs: number,
  untilMs: number,
  minMag: number
): QuakeEvent[] {
  const toLocal = (ms: number) => isoNoMs(new Date(ms + AFAD_TZ_OFFSET_MS))
  const url =
    "https://servisnet.afad.gov.tr/apigateway/deprem/apiv2/event/filter" +
    `?start=${toLocal(sinceMs)}&end=${toLocal(untilMs)}&minmag=${minMag}` +
    `&minlat=${region.minLat}&maxlat=${region.maxLat}` +
    `&minlon=${region.minLon}&maxlon=${region.maxLon}` +
    "&orderby=magnitudedesc&limit=20"
  const data = getJson(requester, url) as Array<{
    eventID: string
    date: string
    latitude: string
    longitude: string
    depth: string
    magnitude: string
    location: string
  }>
  if (!Array.isArray(data)) return []
  return data.map((e) => ({
    source: "AFAD" as const,
    id: `afad-${e.eventID}`,
    timeMs: Date.parse(e.date + "Z") - AFAD_TZ_OFFSET_MS,
    lat: parseFloat(e.latitude),
    lon: parseFloat(e.longitude),
    depthKm: Math.abs(parseFloat(e.depth) || 10),
    mag: parseFloat(e.magnitude),
    place: e.location ?? "",
  }))
}

// ---------------------------------------------------------------- Birleştirme
/** İki olay aynı depremi mi anlatıyor? (zaman ±2 dk, konum ±0.5°) */
export function sameEvent(a: QuakeEvent, b: QuakeEvent): boolean {
  return (
    Math.abs(a.timeMs - b.timeMs) <= 120_000 &&
    Math.abs(a.lat - b.lat) <= 0.5 &&
    Math.abs(a.lon - b.lon) <= 0.5
  )
}

function median(xs: number[]): number {
  const s = [...xs].sort((p, q) => p - q)
  const m = Math.floor(s.length / 2)
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2
}

export type MergedEvent = {
  timeMs: number
  lat: number
  lon: number
  depthKm: number
  mag: number
  sourcesAgreed: number
  place: string
}

/**
 * Üç kaynağın listesini alır; en güçlü depremi bulur ve onu bildiren kaynakların
 * medyanını döner. Tek kaynağın bildirdiği olay, `minSources` altındaysa yok sayılır.
 */
export function mergeStrongest(all: QuakeEvent[], minSources: number): MergedEvent | null {
  if (all.length === 0) return null
  const sorted = [...all].sort((a, b) => b.mag - a.mag)
  for (const cand of sorted) {
    const group = all.filter((e) => sameEvent(e, cand))
    const bySource = new Map<string, QuakeEvent>()
    for (const e of group) if (!bySource.has(e.source)) bySource.set(e.source, e)
    if (bySource.size < minSources) continue
    const g = [...bySource.values()]
    return {
      timeMs: median(g.map((e) => e.timeMs)),
      lat: median(g.map((e) => e.lat)),
      lon: median(g.map((e) => e.lon)),
      depthKm: median(g.map((e) => e.depthKm)),
      mag: median(g.map((e) => e.mag)),
      sourcesAgreed: g.length,
      place: cand.place,
    }
  }
  return null
}
