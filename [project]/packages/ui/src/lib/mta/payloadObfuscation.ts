// XOR+base64 obfuscation, matching core_ui/client/ui/PayloadObfuscation.lua byte-for-byte.
// Obfuscation, not encryption - see docs/UiBridge.md. Must operate on UTF-8 bytes (not
// UTF-16 code units) to match Lua's raw byte strings, hence TextEncoder/TextDecoder below.

const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]!);
  }
  return btoa(binary);
}

function base64ToBytes(base64: string): Uint8Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function xorBytes(data: Uint8Array, key: Uint8Array): Uint8Array {
  const out = new Uint8Array(data.length);
  for (let i = 0; i < data.length; i++) {
    out[i] = data[i]! ^ key[i % key.length]!;
  }
  return out;
}

/** Obfuscates plaintext for transport: UTF-8 -> XOR -> base64. */
export function obfuscatePayload(plaintext: string, key: string | null | undefined): string {
  if (!key) {
    return plaintext;
  }
  const keyBytes = textEncoder.encode(key);
  const plaintextBytes = textEncoder.encode(plaintext);
  return bytesToBase64(xorBytes(plaintextBytes, keyBytes));
}

/** Reverses obfuscatePayload: base64 -> XOR -> UTF-8. */
export function deobfuscatePayload(encoded: string, key: string | null | undefined): string {
  if (!key) {
    return encoded;
  }
  const keyBytes = textEncoder.encode(key);
  const cipherBytes = base64ToBytes(encoded);
  return textDecoder.decode(xorBytes(cipherBytes, keyBytes));
}
