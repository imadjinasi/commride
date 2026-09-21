import { describe, expect, it } from 'vitest';
import { decodePolyline, distanceToRoute, encodePolyline, sampleRoute, validPoint } from '../src/maps/route-geometry';

describe('provider-independent route geometry', () => {
  it('roundtrips the precision-five encoded-polyline reference example', () => {
    const encoded = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';
    const points = [{ latitude: 38.5, longitude: -120.2 }, { latitude: 40.7, longitude: -120.95 }, { latitude: 43.252, longitude: -126.453 }];
    expect(decodePolyline(encoded)).toEqual(points);
    expect(encodePolyline(points)).toBe(encoded);
  });
  it.each(['', '\u0000', '\u007f', '~'.repeat(30), '_p~iF', '?'.repeat(20001)])('rejects malformed or oversized encodings', (value) => {
    expect(decodePolyline(value)).toEqual([]);
  });
  it('rejects out-of-range or nonfinite coordinates', () => {
    expect(validPoint(91, 0)).toBeNull();
    expect(validPoint(0, 181)).toBeNull();
    expect(validPoint(NaN, 0)).toBeNull();
    expect(validPoint(0, Infinity)).toBeNull();
  });
  it('distributes six centers by distance rather than vertex count', () => {
    const points = [{ latitude: 0, longitude: 0 }, { latitude: 0, longitude: 0.001 }, { latitude: 0, longitude: 0.002 }, { latitude: 0, longitude: 1 }];
    const centers = sampleRoute(points);
    expect(centers).toHaveLength(6);
    centers.forEach((point, i) => expect(point.longitude).toBeCloseTo(i / 5, 5));
  });
  it('measures proximity to a segment, not just its endpoints', () => {
    const route = [{ latitude: 0, longitude: 0 }, { latitude: 0, longitude: 1 }];
    expect(distanceToRoute({ latitude: 0, longitude: 0.5 }, route)).toBeCloseTo(0);
    expect(distanceToRoute({ latitude: 1, longitude: 0.5 }, route)).toBeGreaterThan(100000);
  });
  it('handles a narrow antimeridian corridor', () => {
    const route = [{ latitude: 0, longitude: 179.9 }, { latitude: 0, longitude: -179.9 }];
    expect(distanceToRoute({ latitude: 0, longitude: 180 }, route)).toBeCloseTo(0);
  });
});
