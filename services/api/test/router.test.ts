import { describe, expect, it } from 'vitest';

import type { Env } from '../src/env';
import { handleRequest } from '../src/router';

const env: Env = {};

describe('API router', () => {
  it('returns a healthy service response', async () => {
    const response = await handleRequest(
      new Request('https://commride.invalid/health', {
        headers: {
          'x-request-id': 'test-request-1',
        },
      }),
      env,
    );

    expect(response.status).toBe(200);
    expect(response.headers.get('x-request-id')).toBe('test-request-1');

    await expect(response.json()).resolves.toEqual({
      status: 'ok',
      service: 'commride-api',
      version: '0.1.0',
      requestId: 'test-request-1',
    });
  });

  it('returns structured 404 errors', async () => {
    const response = await handleRequest(
      new Request('https://commride.invalid/unknown', {
        headers: {
          'x-request-id': 'test-request-2',
        },
      }),
      env,
    );

    expect(response.status).toBe(404);

    await expect(response.json()).resolves.toEqual({
      error: {
        code: 'not_found',
        message: 'The requested API endpoint does not exist.',
        requestId: 'test-request-2',
      },
    });
  });

  it('rejects unsupported methods on known endpoints', async () => {
    const response = await handleRequest(
      new Request('https://commride.invalid/health', {
        method: 'POST',
        headers: {
          'x-request-id': 'test-request-3',
        },
      }),
      env,
    );

    expect(response.status).toBe(405);

    const body = await response.json() as {
      error: { code: string };
    };

    expect(body.error.code).toBe('method_not_allowed');
  });
});
