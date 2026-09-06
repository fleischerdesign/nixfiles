/**
 * @module dsh-memory/hlc
 * Hybrid Logical Clock (HLC). Provides a causally-consistent, total order for
 * fact versions without relying on wall-clock synchrony. An HLC is
 * `(physicalMs, counter, nodeId)`; the total order is lexicographic over that
 * triple, so two nodes with skewed clocks still agree on a deterministic
 * ordering. The ASCII rendering is zero-padded and lexicographically ordered.
 */

export class HLC {
  physical: number;
  counter: number;
  nodeId: string;

  constructor(physical = 0, counter = 0, nodeId = '') {
    this.physical = physical;
    this.counter = counter;
    this.nodeId = nodeId;
  }

  static fromString(s: string): HLC {
    const [p, c, n] = (s || '').split('|');
    return new HLC(Number(p) || 0, Number(c) || 0, n || '');
  }

  /** Zero-padded so byte-wise string order == logical order. */
  toString(): string {
    const p = String(this.physical).padStart(20, '0');
    const c = String(this.counter).padStart(10, '0');
    return `${p}|${c}|${this.nodeId}`;
  }

  static compare(a: HLC, b: HLC): number {
    if (a.physical !== b.physical) return a.physical - b.physical;
    if (a.counter !== b.counter) return a.counter - b.counter;
    if (a.nodeId === b.nodeId) return 0;
    return a.nodeId < b.nodeId ? -1 : 1;
  }

  static max(a: HLC, b: HLC): HLC {
    return HLC.compare(a, b) >= 0 ? a : b;
  }
}

/**
 * Per-process generator. Produces monotonically increasing HLCs for this
 * node; the counter increments when the physical clock has not advanced.
 */
export class HlcGenerator {
  private last: HLC;
  private readonly nodeId: string;

  constructor(nodeId: string, now = Date.now()) {
    this.nodeId = nodeId;
    this.last = new HLC(now, 0, nodeId);
  }

  /** Next logical timestamp for a fresh event on this node. */
  next(now = Date.now()): HLC {
    if (now > this.last.physical) {
      this.last = new HLC(now, 0, this.nodeId);
    } else {
      this.last = new HLC(this.last.physical, this.last.counter + 1, this.nodeId);
    }
    return this.last;
  }

  /** Absorb a peer HLC (causal observation): advance physical, bump counter. */
  observe(peer: HLC): HLC {
    const local = this.next();
    if (HLC.compare(peer, local) > 0) {
      this.last = new HLC(peer.physical, peer.counter + 1, this.nodeId);
    }
    return this.last;
  }
}

export function hlcsEqual(a: HLC, b: HLC): boolean {
  return HLC.compare(a, b) === 0;
}
