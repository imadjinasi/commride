export interface ApiErrorBody {
  readonly error: {
    readonly code: string;
    readonly message: string;
    readonly requestId: string;
  };
}

export function jsonResponse(
  body: unknown,
  status: number,
  requestId: string,
): Response {
  return Response.json(body, {
    status,
    headers: {
      'cache-control': 'no-store',
      'x-request-id': requestId,
    },
  });
}

export function errorResponse(
  code: string,
  message: string,
  status: number,
  requestId: string,
): Response {
  const body: ApiErrorBody = {
    error: {
      code,
      message,
      requestId,
    },
  };

  return jsonResponse(body, status, requestId);
}
