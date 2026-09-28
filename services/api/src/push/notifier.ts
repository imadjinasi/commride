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

  async notifyRider(message: RiderPushMessage): Promise<PushDeliveryResult> {
    const claimRiderEvent = this.repository.claimRiderEvent;
    const listRiderTokens = this.repository.listRiderTokens;
    if (claimRiderEvent == null || listRiderTokens == null) {
      return { delivered: 0, failed: 0 };
    }

    const claimed = await claimRiderEvent.call(this.repository, {
      eventKey: message.eventKey,
      riderId: message.riderId,
      kind: message.kind,
      createdAt: this.now().toISOString(),
    });
    if (!claimed) {
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
