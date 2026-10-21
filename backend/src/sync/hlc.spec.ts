// Placeholder test: replace with real integration tests (task T4.3).
describe('hlc format', () => {
  it('is lexicographically ordered by time', () => {
    const a = '1761038400000-0000-A1';
    const b = '1761038400001-0000-A1';
    expect(a < b).toBe(true);
  });
});
