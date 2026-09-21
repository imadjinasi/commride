import {
  AuthenticationRequiredError,
  extractBearerToken,
} from './authorization';
import {
  type IdentityVerifier,
  InvalidIdentityTokenError,
} from './identity';
import type { RiderProfile } from '../riders/rider-profile';
import type { RiderRepository } from '../riders/rider-repository';

export type AuthenticatedRiderResult =
  | { readonly rider: RiderProfile }
  | {
      readonly error:
        | 'authentication_required'
        | 'invalid_authentication_token'
        | 'rider_profile_required';
      readonly message: string;
      readonly status: 401 | 409;
    };

export async function authenticateRider(
  request: Request,
  identityVerifier: IdentityVerifier,
  riderRepository: RiderRepository,
): Promise<AuthenticatedRiderResult> {
  let token: string;
  try {
    token = extractBearerToken(request);
  } catch (error) {
    if (error instanceof AuthenticationRequiredError) {
      return {
        error: 'authentication_required',
        message: error.message,
        status: 401,
      };
    }
    throw error;
  }

  let subject: string;
  try {
    const identity = await identityVerifier.verify(token);
    subject = identity.subject;
  } catch (error) {
    if (error instanceof InvalidIdentityTokenError) {
      return {
        error: 'invalid_authentication_token',
        message: error.message,
        status: 401,
      };
    }
    throw error;
  }

  const rider = await riderRepository.findByAuthSubject(subject);
  if (rider == null) {
    return {
      error: 'rider_profile_required',
      message: 'Complete the CommRide Rider profile before using this feature.',
      status: 409,
    };
  }

  return { rider };
}
