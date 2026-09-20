export function realtimeRateLimited(
  lastAcceptedAt: string | undefined,
  now: Date,
  minimumIntervalMs: number,
): boolean {
  if (lastAcceptedAt == null) {
    return false;
  }

  const previous = Date.parse(lastAcceptedAt);
  if (!Number.isFinite(previous)) {
    return false;
  }

  return now.getTime() - previous < minimumIntervalMs;
}
