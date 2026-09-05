/**
 * @module @dsh/ingress/types
 * Formal types for CNCF CloudEvents v1.0 and sliding-window event debouncing.
 */

export interface CloudEvent<T = any> {
  specversion: '1.0';
  id: string;
  source: string;
  type: string;
  time: string;
  datacontenttype?: string;
  data: T;
  // Extensions
  tenant?: string;
  priority?: 'P0' | 'P1' | 'P2';
  occurrences?: number;
}

export interface IngressPluginConfig {
  http?: {
    enabled: boolean;
    host?: string;
    port?: number;
    secret?: string; // HMAC SHA-256 secret
  };
  socket?: {
    enabled: boolean;
    path?: string; // Unix Domain Socket path
  };
  debouncing?: {
    windowMs?: number; // Sliding window duration (default: 15000ms)
  };
}

export interface DebouncedEventRecord {
  event: CloudEvent;
  occurrences: number;
  firstSeenMs: number;
  lastSeenMs: number;
  timer: NodeJS.Timeout;
}
