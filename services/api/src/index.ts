import { ActiveRideRoom } from './active-ride-room';
import type { Env } from './env';
import { handleRequest } from './router';
import { purgeExpiredOperationalData } from './retention';
import { sendUpcomingRideReminders } from './ride-notifications';

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
    controller: ScheduledController,
    env: Env,
    context: ExecutionContext,
  ): Promise<void> {
    if (controller.cron === '17 3 * * *') {
      context.waitUntil(purgeExpiredOperationalData(env));
      return;
    }

    context.waitUntil(sendUpcomingRideReminders(env));
  },
} satisfies ExportedHandler<Env>;
