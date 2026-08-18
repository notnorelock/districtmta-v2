export function uuidv8(): string {
  const timestamp = BigInt(Date.now());
  const bytes = new Uint8Array(16);

  // 48-bit Unix timestamp in milliseconds
  bytes[0] = Number((timestamp >> 40n) & 0xffn);
  bytes[1] = Number((timestamp >> 32n) & 0xffn);
  bytes[2] = Number((timestamp >> 24n) & 0xffn);
  bytes[3] = Number((timestamp >> 16n) & 0xffn);
  bytes[4] = Number((timestamp >> 8n) & 0xffn);
  bytes[5] = Number(timestamp & 0xffn);

  // Random remaining bytes
  for (let i = 6; i < 16; i++) {
    bytes[i] = Math.floor(Math.random() * 256);
  }

  // UUID v8
  bytes[6] = (bytes[6]! & 0x0f) | 0x80;

  // RFC 9562 variant
  bytes[8] = (bytes[8]! & 0x3f) | 0x80;

  const hex = Array.from(
    bytes,
    byte => byte.toString(16).padStart(2, "0"),
  ).join("");

  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20),
  ].join("-");
}