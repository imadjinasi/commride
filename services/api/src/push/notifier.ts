import type { RiderPushMessage, RidePushMessage, PushDeliveryResult } from './models';
import type { PushRepository } from './repository';
import type { PushTransport } from './fcm';

export interface RidePushNotifier {
  notify(message: RidePushMessage): Promise<PushDeliveryResult>;
  notifyRider?(message: RiderPushMessage): Promise<PushDeliveryResult>;
}

export class BestEffortRidePushNotifier implements RidePushNotifier {
  constructor(
    private readonly repository: PushRepository,
    private readonly transport: PushTransport,
    private readonly now: () => Date = () => new Date(),
  ) {}

  // Direct Rider pushes are deduplicated by the caller through the persistent
  // notification inbox (one stored row per Rider and event key).
  async notifyRider(message: RiderPushMessage): Promise<PushDeliveryResult> {
    const listRiderTokens = this.repository.listRiderTokens;
    if (listRiderTokens == null) {
      return { delivered: 0, failed: 0 };
    }

    try {
      const tokens = await listRiderTokens.call(
        this.repository,
        message.riderId,
      );
      return await this.transport.sendToTokens(tokens, {
        title: message.title,
        body: message.body,
        data: message.data,
      });
    } catch {
      return { delivered: 0, failed: 0 };
    }
  }

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
