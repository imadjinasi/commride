import type { Env } from './env';
import { errorResponse, jsonResponse } from './http/json';
import { resolveRequestId } from './request-id';

const SERVICE_NAME = 'commride-api';
const SERVICE_VERSION = '0.1.0';

export async function handleRequest(
  request: Request,
  _env: Env,
): Promise<Response> {
  const requestId = resolveRequestId(request);
  const url = new URL(request.url);

  if (url.pathname === '/health') {
    if (request.method !== 'GET') {
      return errorResponse(
        'method_not_allowed',
        'Only GET is supported for this endpoint.',
        405,
        requestId,
      );
    }

    return jsonResponse(
      {
        status: 'ok',
        service: SERVICE_NAME,
        version: SERVICE_VERSION,
        requestId,
      },
      200,
      requestId,
    );
  }

  if (url.pathname === '/version') {
    if (request.method !== 'GET') {
      return errorResponse(
        'method_not_allowed',
        'Only GET is supported for this endpoint.',
        405,
        requestId,
      );
    }

    return jsonResponse(
      {
        service: SERVICE_NAME,
        version: SERVICE_VERSION,
        requestId,
      },
      200,
      requestId,
    );
  }

  return errorResponse(
    'not_found',
    'The requested API endpoint does not exist.',
    404,
    requestId,
  );
}
