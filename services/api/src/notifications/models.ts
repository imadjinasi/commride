export type NotificationScope = 'account' | 'club';

export interface RiderNotification {
  readonly id: string;
  readonly riderId: string;
  readonly scope: NotificationScope;
  readonly clubId: string | null;
  readonly rideId: string | null;
  readonly eventKey: string;
  readonly kind: string;
  readonly title: string;
  readonly body: string;
  readonly data: Readonly<Record<string, string>>;
  readonly createdAt: string;
  readonly readAt: string | null;
}

export interface CreateNotificationInput {
  readonly eventKey: string;
  readonly scope: NotificationScope;
  readonly clubId?: string | null;
  readonly rideId?: string | null;
  readonly kind: string;
  readonly title: string;
  readonly body: string;
  readonly data?: Readonly<Record<string, string>>;
  readonly createdAt: string;
}
