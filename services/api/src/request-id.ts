const MAX_REQUEST_ID_LENGTH = 128;

export function resolveRequestId(request: Request): string {
  const candidate = request.headers.get('x-request-id')?.trim();

  if (
    candidate != null &&
    candidate.length > 0 &&
    candidate.length <= MAX_REQUEST_ID_LENGTH
  ) {
    return candidate;
  }

  return crypto.randomUUID();
}
