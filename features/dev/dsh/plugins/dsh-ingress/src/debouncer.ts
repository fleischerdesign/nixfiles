import * as crypto from 'node:crypto';
import type { CloudEvent, DebouncedEventRecord } from './types.js';

export type EventDispatchCallback = (event: CloudEvent) => void | Promise<void>;

export class SlidingWindowDebouncer {
  private windowMs: number;
  private onDispatch: EventDispatchCallback;
  private pending = new Map<string, DebouncedEventRecord>();

  constructor(windowMs: number, onDispatch: EventDispatchCallback) {
    this.windowMs = windowMs;
    this.onDispatch = onDispatch;
  }

  /**
   * Deterministic fingerprint for grouping identical alert spikes.
   */
  computeFingerprint(event: CloudEvent): string {
    const raw = `${event.type}:${event.source}:${JSON.stringify(event.data)}`;
    return crypto.createHash('sha256').update(raw).digest('hex');
  }

  /**
   * Ingest an event into the sliding window.
   */
  ingest(event: CloudEvent): void {
    const key = this.computeFingerprint(event);
    const now = Date.now();

    const existing = this.pending.get(key);
    if (existing) {
      existing.occurrences += 1;
      existing.lastSeenMs = now;
      // Sliding window extension or debounce keepalive
      clearTimeout(existing.timer);
      existing.timer = setTimeout(() => this.flush(key), this.windowMs);
    } else {
      const record: DebouncedEventRecord = {
        event,
        occurrences: 1,
        firstSeenMs: now,
        lastSeenMs: now,
        timer: setTimeout(() => this.flush(key), this.windowMs)
      };
      this.pending.set(key, record);
    }
  }

  private flush(key: string): void {
    const record = this.pending.get(key);
    if (!record) return;

    this.pending.delete(key);

    const consolidated: CloudEvent = {
      ...record.event,
      occurrences: record.occurrences
    };

    try {
      this.onDispatch(consolidated);
    } catch {
      // Discard error to prevent debouncer crash
    }
  }

  dispose(): void {
    for (const record of this.pending.values()) {
      clearTimeout(record.timer);
    }
    this.pending.clear();
  }
}
