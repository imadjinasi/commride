import type { RideRole } from '../clubs-rides/models';

export type RideMessageKind = 'chat' | 'announcement';

export interface RideMessage {
  readonly id: string;
  readonly rideId: string;
  readonly senderRiderId: string;
  readonly senderDisplayName: string;
  readonly senderRideRole: RideRole;
  readonly kind: RideMessageKind;
  readonly body: string;
  readonly clientMessageId: string;
  readonly createdAt: string;
}

export interface CreateRideMessageInput extends RideMessage {}

export interface RideMessageCursor {
  readonly createdAt: string;
  readonly id: string;
}

export interface RideMessagePage {
  readonly messages: readonly RideMessage[];
  readonly nextCursor: RideMessageCursor | null;
}
