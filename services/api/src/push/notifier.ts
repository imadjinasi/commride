import type { RidePushMessage, PushDeliveryResult } from './models';
import type { PushRepository } from './repository';
import type { PushTransport } from './fcm';

export interface RidePushNotifier {
  notify(message: RidePushMessage): Promise<PushDeliveryResult>;
}

export class BestEffortRidePushNotifier implements RidePushNotifier {
  constructor(
    private readonly repository: PushRepository,
    private readonly transport: PushTransport,
    private readonly now: () => Date = () => new Date(),
  ) {}

  async notify(message: RidePushMessage): Promise<PushDeliveryResult> {
    const claimed = await this.repository.claimEvent({
      eventKey: message.eventKey,
      rideId: message.rideId,
      kind: message.kind,
      createdAt: this.now().toISOString(),
    });
    if (!claimed) {
      return { delivered: 0, failed: 0 };
    }

    try {
      const tokens = await this.repository.listRideTokens(
        message.rideId,
        {
          excludeRiderId: message.excludeRiderId,
          leaderOnly: message.leaderOnly,
        },
      );
      return await this.transport.sendToTokens(tokens, {
        title: message.title,
        body: message.body,
        data: message.data,
      });
    } catch {
      // Push is deliberately non-authoritative for Ride state.
      return { delivered: 0, failed: 0 };
    }
  }
}
