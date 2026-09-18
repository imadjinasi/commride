import { ActiveRideRoom } from './active-ride-room';
import type { Env } from './env';
import { handleRequest } from './router';

export { ActiveRideRoom };

export default {
  async fetch(
    request: Request,
    env: Env,
    _context: ExecutionContext,
  ): Promise<Response> {
    return handleRequest(request, env);
  },
} satisfies ExportedHandler<Env>;
