import { authenticateRider } from '../auth/authenticated-rider';
import type { IdentityVerifier } from '../auth/identity';
import { errorResponse, jsonResponse } from '../http/json';
import type { RiderRepository } from '../riders/rider-repository';
import {
  type AccountDeletionRepository,
  isDeletionBlocked,
} from './repository';

export interface AccountDeletionHandlerDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly riderRepository: RiderRepository;
  readonly accountDeletionRepository: AccountDeletionRepository;
  readonly now?: () => Date;
}

export function isAccountDeletionRequest(
  pathname: string,
  method: string,
): boolean {
  return (
    pathname === '/v1/me/deletion' ||
    (pathname === '/v1/me' && method === 'DELETE')
  );
}

export async function handleAccountDeletionRequest(
  request: Request,
  url: URL,
  requestId: string,
  dependencies: AccountDeletionHandlerDependencies,
): Promise<Response> {
  const isPreview = url.pathname === '/v1/me/deletion';
  if (isPreview && request.method !== 'GET') {
    return errorResponse(
      'method_not_allowed',
      'Only GET is supported for this endpoint.',
      405,
      requestId,
    );
  }

  const authenticated = await authenticateRider(
    request,
    dependencies.identityVerifier,
    dependencies.riderRepository,
  );
  if ('error' in authenticated) {
    return errorResponse(
      authenticated.error,
      authenticated.message,
      authenticated.status,
      requestId,
    );
  }

  const riderId = authenticated.rider.id;
  const preview = await dependencies.accountDeletionRepository.preview(riderId);

  if (isPreview) {
    return jsonResponse(
      { deletion: { ...preview, blocked: isDeletionBlocked(preview) } },
      200,
      requestId,
    );
  }

  if (isDeletionBlocked(preview)) {
    return jsonResponse(
      {
        error: {
          code: 'account_deletion_blocked',
          message:
            'Transfer Club ownership and finish Active Rides before deleting the account.',
          requestId,
        },
        deletion: { ...preview, blocked: true },
      },
      409,
      requestId,
    );
  }

  await dependencies.accountDeletionRepository.deleteAccount(
    riderId,
    preview.clubsToClose.map((club) => club.clubId),
    (dependencies.now?.() ?? new Date()).toISOString(),
  );

  return jsonResponse(
    {
      deleted: true,
      closedClubs: preview.clubsToClose,
    },
    200,
    requestId,
  );
}
