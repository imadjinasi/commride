export type PushPlatform = 'android' | 'ios';

export interface RiderPushToken {
  readonly id: string;
  readonly riderId: string;
  readonly token: string;
  readonly platform: PushPlatform;
  readonly createdAt: string;
  readonly updatedAt: string;
}

export interface RidePushMessage {
  readonly eventKey: string;
  readonly rideId: string;
  readonly kind: string;
  readonly title: string;
  readonly body: string;
  readonly data: Readonly<Record<string, string>>;
  readonly excludeRiderId?: string;
  readonly leaderOnly?: boolean;
}

export interface PushDeliveryResult {
  readonly delivered: number;
  readonly failed: number;
}
