import type { RideRole } from '../clubs-rides/models';

export interface ActiveRideParticipant {
  readonly riderId: string;
  readonly displayName: string;
  readonly role: RideRole;
}

export interface ActiveRideGateway {
  connect(
    request: Request,
    rideId: string,
    participant: ActiveRideParticipant,
  ): Promise<Response>;

  endRide(rideId: string, endedAt: string): Promise<void>;
}

export class DurableObjectActiveRideGateway
  implements ActiveRideGateway
{
  constructor(private readonly namespace: DurableObjectNamespace) {}

  async connect(
    request: Request,
    rideId: string,
    participant: ActiveRideParticipant,
  ): Promise<Response> {
    const stub = this.namespace.get(
      this.namespace.idFromName(rideId),
    );
    const headers = new Headers(request.headers);
    headers.delete('authorization');
    headers.set('x-commride-ride-id', rideId);
    headers.set('x-commride-rider-id', participant.riderId);
    headers.set(
      'x-commride-rider-display-name',
      participant.displayName,
    );
    headers.set('x-commride-ride-role', participant.role);

    return stub.fetch(
      new Request(
        'https://active-ride.internal/connect',
        {
          method: 'GET',
          headers,
        },
      ),
    );
  }

  async endRide(rideId: string, endedAt: string): Promise<void> {
    const stub = this.namespace.get(
      this.namespace.idFromName(rideId),
    );

    const response = await stub.fetch(
      new Request('https://active-ride.internal/end', {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'x-commride-ride-id': rideId,
        },
        body: JSON.stringify({ endedAt }),
      }),
    );

    if (!response.ok) {
      throw new Error('Active Ride room did not acknowledge Ride end.');
    }
  }
}
