/**
 * Offline invoice numbers: <store 2 chars><device 1 char>/<fy 2 digits>/<6-digit counter>
 * Example: AB1/26/000123  (13 chars, limit is 16, allowed chars A-Z 0-9 / -)
 * VERIFY series rules with your CA before launch.
 */
export function financialYear2(d: Date): string {
  const y = d.getMonth() >= 3 ? d.getFullYear() : d.getFullYear() - 1; // FY starts 1 April
  return String(y % 100).padStart(2, '0');
}

export function formatInvoiceNo(storeCode: string, deviceCode: string, date: Date, counter: number): string {
  if (!/^[A-Z0-9]{2}$/.test(storeCode)) throw new Error('storeCode must be 2 chars A-Z0-9');
  if (!/^[A-Z0-9]$/.test(deviceCode)) throw new Error('deviceCode must be 1 char A-Z0-9');
  if (!Number.isInteger(counter) || counter < 1 || counter > 999999) throw new Error('counter out of range');
  const no = `${storeCode}${deviceCode}/${financialYear2(date)}/${String(counter).padStart(6, '0')}`;
  if (no.length > 16) throw new Error('invoice number too long');
  return no;
}
