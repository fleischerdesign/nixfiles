/**
 * Multi-Pass Zero-Leakage Redaction Engine.
 * Formally sanitizes private secrets, API keys, tokens, and sensitive system paths.
 */

// Known credential and secret patterns
const SENSITIVE_PATTERNS: Array<{ regex: RegExp; placeholder: string }> = [
  // OpenAI & DeepSeek API Keys
  { regex: /sk-[A-Za-z0-9_-]{20,}/g, placeholder: '[REDACTED_API_KEY]' },
  // GitHub Personal Access Tokens
  { regex: /gh[pousr]_[A-Za-z0-9]{36,}/g, placeholder: '[REDACTED_GH_TOKEN]' },
  // Anthropic API Keys
  { regex: /sk-ant-[A-Za-z0-9_-]{20,}/g, placeholder: '[REDACTED_ANTHROPIC_KEY]' },
  // Age Secret Keys & Public Keys
  { regex: /AGE-SECRET-KEY-[A-Za-z0-9]{50,}/g, placeholder: '[REDACTED_AGE_SECRET_KEY]' },
  // Standard Bearer Tokens
  { regex: /Bearer\s+([A-Za-z0-9._~+/-]{20,})/gi, placeholder: 'Bearer [REDACTED_BEARER_TOKEN]' },
  // Private Key Blocks
  { regex: /-----BEGIN\s+[A-Z\s]+PRIVATE\s+KEY-----[\s\S]*?-----END\s+[A-Z\s]+PRIVATE\s+KEY-----/g, placeholder: '[REDACTED_PRIVATE_KEY_BLOCK]' },
  // SOPS Secret Files
  { regex: /\/etc\/nixos\/secrets\/[A-Za-z0-9._-]+\.yaml/g, placeholder: '/etc/nixos/secrets/[REDACTED_SECRET_FILE].yaml' },
  // Generic key/value password assignments
  { regex: /(password|secret|token|api_key|apikey|auth_token)\s*[:=]\s*["'][^"'\n]{6,}["']/gi, placeholder: '$1: "[REDACTED_CREDENTIAL]"' },
];

/**
 * Redact sensitive secrets from text.
 */
export function redactText(text: string): string {
  if (!text || typeof text !== 'string') return text;
  let result = text;
  for (const { regex, placeholder } of SENSITIVE_PATTERNS) {
    result = result.replace(regex, placeholder);
  }
  return result;
}

/**
 * Virtualize sensitive local file paths (e.g., /home/philipp/...).
 */
export function virtualizePaths(text: string, homeDir?: string): string {
  if (!text || typeof text !== 'string') return text;
  const home = homeDir || process.env.HOME || '/home';
  // Replace /home/<user> with ~
  const homeRegex = new RegExp(home.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g');
  return text.replace(homeRegex, '~');
}

/**
 * Deep recursive redaction of arbitrary JSON structures (messages, tool calls, attachments).
 */
export function sanitizeMessagePayload(data: any): any {
  if (data === null || data === undefined) return data;
  if (typeof data === 'string') {
    return virtualizePaths(redactText(data));
  }
  if (Array.isArray(data)) {
    return data.map((item) => sanitizeMessagePayload(item));
  }
  if (typeof data === 'object') {
    const sanitized: Record<string, any> = {};
    for (const [key, value] of Object.entries(data)) {
      // Omit direct internal auth or secret fields
      if (/^(cookie|authorization|auth|secret|signingKey)$/i.test(key)) {
        sanitized[key] = '[REDACTED]';
      } else {
        sanitized[key] = sanitizeMessagePayload(value);
      }
    }
    return sanitized;
  }
  return data;
}
