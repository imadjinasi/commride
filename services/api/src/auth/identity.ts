export interface AuthenticatedIdentity {
  readonly subject: string;
  readonly email?: string;
  readonly emailVerified?: boolean;
}

export interface IdentityVerifier {
  verify(token: string): Promise<AuthenticatedIdentity>;
}

export class InvalidIdentityTokenError extends Error {
  constructor(message = 'The authentication token is invalid or expired.') {
    super(message);
    this.name = 'InvalidIdentityTokenError';
  }
}
