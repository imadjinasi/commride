export class AuthenticationRequiredError extends Error {
  constructor(message = 'A valid Bearer token is required.') {
    super(message);
    this.name = 'AuthenticationRequiredError';
  }
}

export function extractBearerToken(request: Request): string {
  const authorization = request.headers.get('authorization');
  if (authorization == null) {
    throw new AuthenticationRequiredError();
  }

  const match = /^Bearer\s+(.+)$/i.exec(authorization.trim());
  const token = match?.[1]?.trim();

  if (token == null || token.length === 0) {
    throw new AuthenticationRequiredError();
  }

  return token;
}
