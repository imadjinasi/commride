import { authenticateRider } from '../auth/authenticated-rider';
import type { IdentityVerifier } from '../auth/identity';
import { errorResponse, jsonResponse } from '../http/json';
import type { RiderRepository } from '../riders/rider-repository';
import type { NotificationScope } from './models';
import type { NotificationRepository } from './repository';

export interface NotificationHandlerDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly riderRepository: RiderRepository;
  readonly notificationRepository: NotificationRepository;
  readonly now?: () => Date;
}

type NotificationPath =
  | { readonly kind: 'list' }
  | { readonly kind: 'read'; readonly notificationId: string };

export function isNotificationPath(pathname: string): boolean {
  return matchPath(pathname) != null;
}

export async function handleNotificationRequest(
  request: Request,
  url: URL,
  requestId: string,
  dependencies: NotificationHandlerDependencies,
): Promise<Response | null> {
  const path = matchPath(url.pathname);
  if (path == null) {
    return null;
  }

  const authentication = await authenticateRider(
    request,
    dependencies.identityVerifier,
    dependencies.riderRepository,
  );
  if ('error' in authentication) {
    return errorResponse(
      authentication.error,
      authentication.message,
      authentication.status,
      requestId,
    );
  }

  if (path.kind === 'list') {
    if (request.method !== 'GET') {
      return errorResponse(
        'method_not_allowed',
        'Only GET is supported for this endpoint.',
        405,
        requestId,
      );
    }

    const scope = parseScope(url.searchParams.get('scope'));
    if (scope === 'invalid') {
      return errorResponse(
        'invalid_notification_scope',
        'scope must be account or club.',
        400,
        requestId,
      );
    }

    const notifications = await dependencies.notificationRepository.listForRider(
      authentication.rider.id,
      {
        scope: scope ?? undefined,
        clubId: url.searchParams.get('clubId')?.trim() || undefined,
        limit: parseLimit(url.searchParams.get('limit')),
      },
    );
    return jsonResponse({ notifications }, 200, requestId);
  }

  if (request.method !== 'POST') {
    return errorResponse(
      'method_not_allowed',
      'Only POST is supported for this endpoint.',
      405,
      requestId,
    );
  }

  const marked = await dependencies.notificationRepository.markRead(
    authentication.rider.id,
    path.notificationId,
    (dependencies.now?.() ?? new Date()).toISOString(),
  );
  if (!marked) {
    return errorResponse(
      'notification_not_found',
      'The notification does not exist for this Rider.',
      404,
      requestId,
    );
  }
  return jsonResponse({ read: true }, 200, requestId);
}

function matchPath(pathname: string): NotificationPath | null {
  if (pathname === '/v1/me/notifications') {
    return { kind: 'list' };
  }
  const read = /^\/v1\/me\/notifications\/([^/]+)\/read$/.exec(pathname);
  return read?.[1] == null
    ? null
    : { kind: 'read', notificationId: decodeURIComponent(read[1]) };
}

function parseScope(
  raw: string | null,
): NotificationScope | null | 'invalid' {
  if (raw == null || raw.trim().length === 0) {
    return null;
  }
  return raw === 'account' || raw === 'club' ? raw : 'invalid';
}

function parseLimit(raw: string | null): number | undefined {
  if (raw == null || raw.trim().length === 0) {
    return undefined;
  }
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) ? parsed : undefined;
}
