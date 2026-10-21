import { describe, expect, it } from 'vitest';
import { Hlc } from './hlc';
import { formatInvoiceNo } from './billNumber';

describe('Hlc', () => {
  it('is strictly increasing even when the clock does not move', () => {
    const h = new Hlc('A1', () => 1_761_038_400_000);
    const a = h.next(); const b = h.next();
    expect(a < b).toBe(true);
  });
  it('advances past a remote clock', () => {
    const h = new Hlc('A1', () => 1_000_000_000_000);
    h.observe('1761038400000-0005-B2');
    expect(h.next() > '1761038400000-0005-B2').toBe(true);
  });
});

describe('invoice number', () => {
  it('fits 16 chars and uses the financial year', () => {
    const no = formatInvoiceNo('AB', '1', new Date(2026, 4, 1), 123);
    expect(no).toBe('AB1/26/000123');
    expect(no.length).toBeLessThanOrEqual(16);
  });
  it('rolls the FY on 1 April', () => {
    expect(formatInvoiceNo('AB', '1', new Date(2027, 0, 15), 1)).toContain('/26/');
    expect(formatInvoiceNo('AB', '1', new Date(2027, 3, 1), 1)).toContain('/27/');
  });
});
