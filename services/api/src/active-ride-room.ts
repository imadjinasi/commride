import type { Env } from './env';
import { errorResponse } from './http/json';
import { resolveRequestId } from './request-id';

/**
 * Placeholder Durable Object for the future Active Ride realtime room.
 *
 * It deliberately does not accept WebSocket sessions yet. Realtime protocol,
 * authorization, RiderPresence freshness, and persistence semantics must be
 * implemented together with their dedicated acceptance criteria.
 */
export class ActiveRideRoom {
  constructor(
    private readonly state: DurableObjectState,
    private readonly env: Env,
  ) {}

  async fetch(request: Request): Promise<Response> {
    void this.state;
    void this.env;

    const requestId = resolveRequestId(request);

    return errorResponse(
      'realtime_not_implemented',
      'Active Ride realtime is not implemented in this scaffold.',
      501,
      requestId,
    );
  }
}
