/**
 * @module dsh-capability/error
 * Typed error for the capability layer. Every denial and every malformed
 * input is reported as a CapabilityError so callers can distinguish a
 * *policy denial* (Deny) from a *policy/programming fault* (Invalid) — and,
 * crucially, can never confuse the two and fall through to an allow.
 */
export type CapabilityErrorCode =
  | 'deny' // explicit policy denial (no matching grant)
  | 'invalid-path' // path could not be canonicalized (NUL / escape / non-absolute)
  | 'expired' // grant past its TTL
  | 'replayed' // nonce/ttl replay
  | 'widening' // attenuation would exceed its parent
  | 'bad-signature' // attestation does not verify
  | 'revoked'; // grant revoked short of its TTL

export class CapabilityError extends Error {
  readonly code: CapabilityErrorCode;

  constructor(code: CapabilityErrorCode, message: string) {
    super(message);
    this.name = 'CapabilityError';
    this.code = code;
  }
}

/** Convenience constructor for the default-deny path. */
export function deny(message: string): CapabilityError {
  return new CapabilityError('deny', message);
}
