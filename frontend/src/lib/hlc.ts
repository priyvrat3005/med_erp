/** Hybrid Logical Clock, fixed width: <13-digit ms>-<4 hex counter>-<device code> */
export class Hlc {
  private lastMs = 0;
  private counter = 0;
  constructor(private readonly deviceCode: string, now: () => number = Date.now) {
    this.now = now;
  }
  private now: () => number;

  next(): string {
    const t = this.now();
    if (t > this.lastMs) { this.lastMs = t; this.counter = 0; } else { this.counter += 1; }
    return this.format(this.lastMs, this.counter);
  }

  /** Call when receiving a remote HLC so local time never goes behind it. */
  observe(remote: string): void {
    const ms = Number(remote.slice(0, 13));
    const ctr = parseInt(remote.slice(14, 18), 16);
    if (ms > this.lastMs || (ms === this.lastMs && ctr > this.counter)) {
      this.lastMs = ms;
      this.counter = ctr;
    }
  }

  private format(ms: number, counter: number): string {
    return `${String(ms).padStart(13, '0')}-${counter.toString(16).padStart(4, '0')}-${this.deviceCode}`;
  }
}
