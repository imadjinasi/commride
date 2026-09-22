import type { GeoPoint } from './models';

const R = 6371000;
const RAD = Math.PI / 180;
export const MAX_POLYLINE_LENGTH = 20000;

export function validPoint(latitude: unknown, longitude: unknown): GeoPoint | null {
  return typeof latitude === 'number' && Number.isFinite(latitude) &&
    latitude >= -90 && latitude <= 90 &&
    typeof longitude === 'number' && Number.isFinite(longitude) &&
    longitude >= -180 && longitude <= 180 ? { latitude, longitude } : null;
}

function wrap(delta: number): number {
  return ((delta + 540) % 360) - 180;
}

export function distanceMeters(a: GeoPoint, b: GeoPoint): number {
  const p = (b.latitude - a.latitude) * RAD;
  const q = wrap(b.longitude - a.longitude) * RAD;
  const h = Math.sin(p / 2) ** 2 + Math.cos(a.latitude * RAD) *
    Math.cos(b.latitude * RAD) * Math.sin(q / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(Math.min(1, Math.max(0, h))));
}

/** Distance-spaced search centers, capped independently of vertex density. */
export function sampleRoute(points: readonly GeoPoint[], maximum = 6): GeoPoint[] {
  if (points.length < 2 || maximum < 2) return [...points.slice(0, 1)];
  const lengths = [0];
  for (let i = 1; i < points.length; i++) {
    lengths.push(lengths[i - 1]! + distanceMeters(points[i - 1]!, points[i]!));
  }
  const total = lengths.at(-1)!;
  if (total < 1) return [points[0]!];
  const count = Math.min(maximum, Math.max(2, Math.ceil(total / 8000) + 1));
  const result: GeoPoint[] = [];
  let segment = 1;
  for (let i = 0; i < count; i++) {
    const target = total * i / (count - 1);
    while (segment < points.length - 1 && lengths[segment]! < target) segment++;
    const a = points[segment - 1]!, b = points[segment]!;
    const length = lengths[segment]! - lengths[segment - 1]!;
    const t = length === 0 ? 0 : (target - lengths[segment - 1]!) / length;
    result.push({
      latitude: a.latitude + (b.latitude - a.latitude) * t,
      longitude: wrap(a.longitude + wrap(b.longitude - a.longitude) * t),
    });
  }
  return result;
}

/** Local tangent-plane distance for a narrow pilot search corridor, not road access. */
export function distanceToRoute(point: GeoPoint, route: readonly GeoPoint[]): number {
  let best = Number.POSITIVE_INFINITY;
  const scaleX = R * RAD * Math.cos(point.latitude * RAD), scaleY = R * RAD;
  for (let i = 1; i < route.length; i++) {
    const a = route[i - 1]!, b = route[i]!;
    const ax = wrap(a.longitude - point.longitude) * scaleX;
    const ay = (a.latitude - point.latitude) * scaleY;
    const bx = ax + wrap(b.longitude - a.longitude) * scaleX;
    const by = (b.latitude - point.latitude) * scaleY;
    const dx = bx - ax, dy = by - ay, squared = dx * dx + dy * dy;
    const t = squared === 0 ? 0 : Math.min(1, Math.max(0, -(ax * dx + ay * dy) / squared));
    best = Math.min(best, Math.hypot(ax + t * dx, ay + t * dy));
  }
  return best;
}

export function encodePolyline(points: readonly GeoPoint[]): string {
  let lat = 0, lon = 0, encoded = '';
  function signed(value: number): string {
    let n = value < 0 ? -value * 2 - 1 : value * 2, part = '';
    while (n >= 32) {
      part += String.fromCharCode((n % 32) + 95);
      n = Math.floor(n / 32);
    }
    return part + String.fromCharCode(n + 63);
  }
  for (const point of points) {
    if (validPoint(point.latitude, point.longitude) == null) throw new Error('invalid_point');
    const nextLat = Math.round(point.latitude * 1e5), nextLon = Math.round(point.longitude * 1e5);
    encoded += signed(nextLat - lat) + signed(nextLon - lon);
    lat = nextLat;
    lon = nextLon;
  }
  return encoded;
}

export function decodePolyline(encoded: string): GeoPoint[] {
  return decodePolylineWithPrecision(encoded, 5);
}

export function decodePolyline6(encoded: string): GeoPoint[] {
  return decodePolylineWithPrecision(encoded, 6);
}

function decodePolylineWithPrecision(
  encoded: string,
  precision: 5 | 6,
): GeoPoint[] {
  if (encoded.length === 0 || encoded.length > MAX_POLYLINE_LENGTH) return [];
  const points: GeoPoint[] = [];
  let index = 0, lat = 0, lon = 0;
  const scale = precision === 6 ? 1e6 : 1e5;
  function signed(): number {
    let n = 0, shift = 0;
    while (index < encoded.length && shift <= 30) {
      const value = encoded.charCodeAt(index++) - 63;
      if (value < 0 || value > 63) throw new Error('invalid_polyline');
      n += (value & 31) * 2 ** shift;
      if (value < 32) return n % 2 === 1 ? -(n + 1) / 2 : n / 2;
      shift += 5;
    }
    throw new Error('invalid_polyline');
  }
  try {
    while (index < encoded.length) {
      lat += signed();
      lon += signed();
      const point = validPoint(lat / scale, lon / scale);
      if (point == null) return [];
      points.push(point);
    }
  } catch { return []; }
  return points;
}
