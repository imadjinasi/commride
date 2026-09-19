import { ActiveRideRoom } from './active-ride-room';
import type { Env } from './env';
import { handleRequest } from './router';
import { purgeExpiredOperationalData } from './retention';

export { ActiveRideRoom };

export default {
  async fetch(
    request: Request,
    env: Env,
    _context: ExecutionContext,
  ): Promise<Response> {
    return handleRequest(request, env);
  },

  async scheduled(
    _controller: ScheduledController,
    env: Env,
    context: ExecutionContext,
  ): Promise<void> {
    context.waitUntil(purgeExpiredOperationalData(env));
  },
} satisfies ExportedHandler<Env>;
