// Dependency-free structural IPA verification on Windows, macOS or Linux.
// The packaging script additionally verifies the real signatures with Apple's
// codesign. This verifier inspects ZIP CRCs, device Mach-O headers and embedded
// entitlement blobs; it does not replace cryptographic codesign verification.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { inflateRawSync } from 'node:zlib';

const MAX_ARCHIVE_BYTES = 64 * 1024 * 1024;
const MAX_EXPANDED_BYTES = 128 * 1024 * 1024;
const APP = 'Payload/Datenblick.app/';
const WIDGET = APP + 'PlugIns/DatenblickWidget.appex/';
const ensure = (condition, message) => { if (!condition) throw new Error(message); };
const within = (buffer, offset, size) => Number.isSafeInteger(offset) && offset >= 0 && size >= 0 && offset + size <= buffer.length;
const crcTable = Array.from({ length: 256 }, (_, index) => {
  let value = index;
  for (let bit = 0; bit < 8; bit++) value = value & 1 ? 0xEDB88320 ^ (value >>> 1) : value >>> 1;
  return value >>> 0;
});
const crc32 = buffer => {
  let value = 0xFFFFFFFF;
  for (const byte of buffer) value = crcTable[(value ^ byte) & 255] ^ (value >>> 8);
  return (value ^ 0xFFFFFFFF) >>> 0;
};

class ZipArchive {
  constructor(buffer) {
    ensure(buffer.length <= MAX_ARCHIVE_BYTES, 'IPA exceeds the 64 MiB artifact limit.');
    this.buffer = buffer;
    this.entries = new Map();
    let end = -1;
    for (let offset = buffer.length - 22; offset >= Math.max(0, buffer.length - 65_557); offset--) {
      if (buffer.readUInt32LE(offset) === 0x06054B50 && offset + 22 + buffer.readUInt16LE(offset + 20) === buffer.length) {
        end = offset;
        break;
      }
    }
    ensure(end >= 0, 'ZIP end-of-directory record is missing.');
    ensure(buffer.readUInt16LE(end + 4) === 0 && buffer.readUInt16LE(end + 6) === 0, 'Multi-disk ZIPs are unsupported.');
    const count = buffer.readUInt16LE(end + 10);
    ensure(count === buffer.readUInt16LE(end + 8) && count > 0 && count < 10_000, 'Invalid ZIP entry count.');
    const directorySize = buffer.readUInt32LE(end + 12);
    const directoryOffset = buffer.readUInt32LE(end + 16);
    ensure(directoryOffset + directorySize === end, 'Unexpected or ZIP64 directory layout.');
    let offset = directoryOffset;
    let expanded = 0;
    for (let index = 0; index < count; index++) {
      ensure(within(buffer, offset, 46) && buffer.readUInt32LE(offset) === 0x02014B50, 'Invalid ZIP directory entry.');
      const nameLength = buffer.readUInt16LE(offset + 28);
      const extraLength = buffer.readUInt16LE(offset + 30);
      const commentLength = buffer.readUInt16LE(offset + 32);
      const size = 46 + nameLength + extraLength + commentLength;
      ensure(within(buffer, offset, size) && offset + size <= end, 'Truncated ZIP directory.');
      const name = buffer.subarray(offset + 46, offset + 46 + nameLength).toString('utf8');
      ensure(name.startsWith('Payload/') && !name.includes('\\') && !name.includes('\0')
        && !name.split('/').some(part => part === '.' || part === '..'), 'Unsafe or unexpected archive path.');
      ensure(!this.entries.has(name), `Duplicate archive path: ${name}`);
      const flags = buffer.readUInt16LE(offset + 8);
      const method = buffer.readUInt16LE(offset + 10);
      const compressedSize = buffer.readUInt32LE(offset + 20);
      const uncompressedSize = buffer.readUInt32LE(offset + 24);
      ensure(!(flags & 1) && [0, 8].includes(method), 'Encrypted or unsupported ZIP compression.');
      ensure(uncompressedSize <= MAX_ARCHIVE_BYTES, 'A ZIP entry exceeds the size limit.');
      expanded += uncompressedSize;
      ensure(expanded <= MAX_EXPANDED_BYTES, 'Expanded IPA exceeds the 128 MiB limit.');
      this.entries.set(name, {
        flags, method, compressedSize, uncompressedSize,
        checksum: buffer.readUInt32LE(offset + 16),
        mode: buffer.readUInt32LE(offset + 38) >>> 16,
        localOffset: buffer.readUInt32LE(offset + 42)
      });
      offset += size;
    }
    ensure(offset === end, 'ZIP directory size does not match its entries.');
  }

  read(name) {
    const entry = this.entries.get(name);
    ensure(entry, `Missing IPA entry: ${name}`);
    const { buffer } = this;
    const offset = entry.localOffset;
    ensure(within(buffer, offset, 30) && buffer.readUInt32LE(offset) === 0x04034B50, `Invalid ZIP local header: ${name}`);
    const nameLength = buffer.readUInt16LE(offset + 26);
    const extraLength = buffer.readUInt16LE(offset + 28);
    const contentStart = offset + 30 + nameLength + extraLength;
    ensure(within(buffer, offset + 30, nameLength + extraLength) && within(buffer, contentStart, entry.compressedSize), 'Truncated ZIP content.');
    ensure(buffer.subarray(offset + 30, offset + 30 + nameLength).toString('utf8') === name, 'ZIP local and central names differ.');
    ensure(buffer.readUInt16LE(offset + 8) === entry.method && !(buffer.readUInt16LE(offset + 6) & 1), 'ZIP local compression differs.');
    const compressed = buffer.subarray(contentStart, contentStart + entry.compressedSize);
    const data = entry.method === 0 ? compressed : inflateRawSync(compressed, { maxOutputLength: MAX_ARCHIVE_BYTES });
    ensure(data.length === entry.uncompressedSize && crc32(data) === entry.checksum, `ZIP checksum/length mismatch: ${name}`);
    return data;
  }
}

const decodeXML = text => text.replace(/&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos);/gi, (_, entity) => {
  const named = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };
  if (entity[0] !== '#') return named[entity.toLowerCase()];
  const point = entity[1].toLowerCase() === 'x' ? parseInt(entity.slice(2), 16) : parseInt(entity.slice(1), 10);
  ensure(point <= 0x10FFFF && !(point >= 0xD800 && point <= 0xDFFF), 'Invalid XML character entity.');
  return String.fromCodePoint(point);
});
const escapeRegex = text => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const plistText = data => {
  const text = data.toString('utf8').replace(/\0+$/, '');
  ensure(text.includes('<plist') && text.includes('</plist>'), 'Expected an XML plist; package-ipa.py normalizes Info.plist before signing.');
  return text;
};
const plistValue = (text, key, type) => {
  const matches = [...text.matchAll(new RegExp(`<key>\\s*${escapeRegex(key)}\\s*</key>\\s*<${type}>([\\s\\S]*?)</${type}>`, 'g'))];
  ensure(matches.length === 1, `Expected exactly one plist ${type} for ${key}.`);
  return matches[0][1];
};
const plistString = (text, key) => decodeXML(plistValue(text, key, 'string'));
const plistStrings = (text, key) => {
  const inner = plistValue(text, key, 'array');
  const values = [...inner.matchAll(/<string>([\s\S]*?)<\/string>/g)].map(match => decodeXML(match[1]));
  ensure(inner.replace(/<string>[\s\S]*?<\/string>/g, '').trim() === '', `Unsupported array values for ${key}.`);
  return values;
};

function inspectMachO(data) {
  ensure(within(data, 0, 32) && data.readUInt32LE(0) === 0xFEEDFACF, 'Expected a thin little-endian 64-bit Mach-O.');
  ensure(data.readUInt32LE(4) === 0x0100000C && data.readUInt32LE(12) === 2, 'Expected an arm64 MH_EXECUTE binary.');
  const count = data.readUInt32LE(16);
  const commandsEnd = 32 + data.readUInt32LE(20);
  ensure(count < 10_000 && within(data, 32, commandsEnd - 32), 'Invalid Mach-O load-command bounds.');
  let offset = 32;
  let platform;
  let signature;
  for (let index = 0; index < count; index++) {
    ensure(within(data, offset, 8) && offset + 8 <= commandsEnd, 'Truncated Mach-O load command.');
    const command = data.readUInt32LE(offset);
    const size = data.readUInt32LE(offset + 4);
    ensure(size >= 8 && offset + size <= commandsEnd, 'Invalid Mach-O command size.');
    if (command === 0x32) {
      ensure(size >= 24, 'Invalid LC_BUILD_VERSION command.');
      platform = data.readUInt32LE(offset + 8);
    }
    if (command === 0x1D) {
      ensure(size >= 16 && !signature, 'Invalid or duplicate code-signature command.');
      const start = data.readUInt32LE(offset + 8);
      const length = data.readUInt32LE(offset + 12);
      ensure(within(data, start, length), 'Code signature is outside the executable.');
      signature = data.subarray(start, start + length);
    }
    offset += size;
  }
  ensure(offset === commandsEnd && platform === 2, 'Executable must target physical iOS (not Simulator or Mac Catalyst).');
  ensure(signature && within(signature, 0, 12) && signature.readUInt32BE(0) === 0xFADE0CC0, 'Missing embedded code-signature superblob.');
  const length = signature.readUInt32BE(4);
  const slots = signature.readUInt32BE(8);
  ensure(length <= signature.length && slots < 1_000 && 12 + slots * 8 <= length, 'Invalid signature superblob bounds.');
  let adHoc = false;
  let entitlements;
  for (let index = 0; index < slots; index++) {
    const type = signature.readUInt32BE(12 + index * 8);
    const start = signature.readUInt32BE(16 + index * 8);
    ensure(start + 8 <= length, 'Invalid code-signature slot.');
    const magic = signature.readUInt32BE(start);
    const size = signature.readUInt32BE(start + 4);
    ensure(size >= 8 && start + size <= length, 'Truncated code-signature blob.');
    if (type === 0 && magic === 0xFADE0C02) {
      ensure(size >= 16, 'CodeDirectory is truncated.');
      adHoc = (signature.readUInt32BE(start + 12) & 2) !== 0;
    }
    if (type === 5 && magic === 0xFADE7171) {
      ensure(!entitlements, 'Duplicate entitlement signature blobs.');
      entitlements = plistText(signature.subarray(start + 8, start + size));
    }
  }
  ensure(adHoc && entitlements, 'Expected an ad-hoc signature retaining XML App Group entitlements.');
  return { groups: plistStrings(entitlements, 'com.apple.security.application-groups') };
}

function verifyArchive(buffer) {
  const zip = new ZipArchive(buffer);
  for (const name of zip.entries.keys()) {
    ensure(name === 'Payload/' || name.startsWith(APP), 'IPA contains an unexpected app or top-level file.');
    if (name.startsWith(APP + 'PlugIns/')) {
      ensure(name === APP + 'PlugIns/' || name.startsWith(WIDGET), 'IPA contains an unexpected extension.');
    }
    zip.read(name); // Validate every entry's CRC before inspecting the required files.
  }
  const appInfo = plistText(zip.read(APP + 'Info.plist'));
  const widgetInfo = plistText(zip.read(WIDGET + 'Info.plist'));
  const appID = plistString(appInfo, 'CFBundleIdentifier');
  ensure(/^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/.test(appID), 'Invalid app bundle identifier.');
  ensure(plistString(widgetInfo, 'CFBundleIdentifier') === appID + '.widget', 'Widget bundle identifier is not nested under the app.');
  ensure(plistString(appInfo, 'CFBundlePackageType') === 'APPL' && plistString(widgetInfo, 'CFBundlePackageType') === 'XPC!', 'Invalid bundle package types.');
  ensure(plistString(widgetInfo, 'NSExtensionPointIdentifier') === 'com.apple.widgetkit-extension', 'Extension is not a WidgetKit widget.');
  const group = plistString(appInfo, 'AppGroupIdentifier');
  ensure(/^group\.[A-Za-z0-9.-]+$/.test(group) && plistString(widgetInfo, 'AppGroupIdentifier') === group, 'App Group Info.plist values differ or are unresolved.');
  for (const [base, info] of [[APP, appInfo], [WIDGET, widgetInfo]]) {
    const executable = plistString(info, 'CFBundleExecutable');
    ensure(/^[A-Za-z0-9_-][A-Za-z0-9_.-]*$/.test(executable), 'Unsafe bundle executable name.');
    const entry = zip.entries.get(base + executable);
    ensure(entry && (entry.mode & 0o111) !== 0 && (entry.mode & 0o170000) === 0o100000, 'Executable is missing, a symlink, or lacks execute permission.');
    const { groups } = inspectMachO(zip.read(base + executable));
    ensure(groups.length === 1 && groups[0] === group, 'Signed App Group entitlements do not match both bundles.');
    ensure(!zip.entries.has(base + 'embedded.mobileprovision'), 'Ad-hoc artifact must not retain an old provisioning profile.');
  }
  return { appID, group, entries: zip.entries.size };
}

function selfTest() {
  // Synthetic headers test the parser's rejection paths. They are not an iOS
  // build and cannot establish cryptographic signature validity or installation.
  const xml = values => `<?xml version="1.0"?><plist version="1.0"><dict>${Object.entries(values).map(([key, value]) => `<key>${key}</key>${Array.isArray(value) ? `<array>${value.map(item => `<string>${item}</string>`).join('')}</array>` : `<string>${value}</string>`}`).join('')}</dict></plist>`;
  const group = 'group.de.datenblick.app';
  const binary = ({ platform = 2, signedGroup = group, adHoc = true } = {}) => {
    const entitlements = Buffer.from(xml({ 'com.apple.security.application-groups': [signedGroup] }));
    const signature = Buffer.alloc(52 + entitlements.length);
    signature.writeUInt32BE(0xFADE0CC0, 0);
    signature.writeUInt32BE(signature.length, 4);
    signature.writeUInt32BE(2, 8);
    signature.writeUInt32BE(0, 12);
    signature.writeUInt32BE(28, 16);
    signature.writeUInt32BE(5, 20);
    signature.writeUInt32BE(44, 24);
    signature.writeUInt32BE(0xFADE0C02, 28);
    signature.writeUInt32BE(16, 32);
    signature.writeUInt32BE(adHoc ? 2 : 0, 40);
    signature.writeUInt32BE(0xFADE7171, 44);
    signature.writeUInt32BE(8 + entitlements.length, 48);
    entitlements.copy(signature, 52);
    const header = Buffer.alloc(72);
    header.writeUInt32LE(0xFEEDFACF, 0);
    header.writeUInt32LE(0x0100000C, 4);
    header.writeUInt32LE(2, 12);
    header.writeUInt32LE(2, 16);
    header.writeUInt32LE(40, 20);
    header.writeUInt32LE(0x32, 32);
    header.writeUInt32LE(24, 36);
    header.writeUInt32LE(platform, 40);
    header.writeUInt32LE(0x1D, 56);
    header.writeUInt32LE(16, 60);
    header.writeUInt32LE(72, 64);
    header.writeUInt32LE(signature.length, 68);
    return Buffer.concat([header, signature]);
  };
  const fixture = options => {
    const settings = { widgetID: 'de.datenblick.app.widget', infoGroup: group, ...options };
    return [
      { name: APP + 'Info.plist', data: Buffer.from(xml({ CFBundleIdentifier: 'de.datenblick.app', CFBundlePackageType: 'APPL', CFBundleExecutable: 'Datenblick', AppGroupIdentifier: group })) },
      { name: WIDGET + 'Info.plist', data: Buffer.from(xml({ CFBundleIdentifier: settings.widgetID, CFBundlePackageType: 'XPC!', CFBundleExecutable: 'DatenblickWidget', AppGroupIdentifier: settings.infoGroup, NSExtensionPointIdentifier: 'com.apple.widgetkit-extension' })) },
      { name: APP + 'Datenblick', data: binary(settings), mode: 0o100755 },
      { name: WIDGET + 'DatenblickWidget', data: binary(settings), mode: 0o100755 }
    ];
  };
  const makeZip = entries => {
    const contents = [];
    const directory = [];
    let offset = 0;
    for (const { name, data, mode = 0o100644 } of entries) {
      const filename = Buffer.from(name);
      const local = Buffer.alloc(30);
      local.writeUInt32LE(0x04034B50, 0);
      local.writeUInt32LE(crc32(data), 14);
      local.writeUInt32LE(data.length, 18);
      local.writeUInt32LE(data.length, 22);
      local.writeUInt16LE(filename.length, 26);
      contents.push(local, filename, data);
      const central = Buffer.alloc(46);
      central.writeUInt32LE(0x02014B50, 0);
      central.writeUInt16LE(0x314, 4);
      central.writeUInt32LE(crc32(data), 16);
      central.writeUInt32LE(data.length, 20);
      central.writeUInt32LE(data.length, 24);
      central.writeUInt16LE(filename.length, 28);
      central.writeUInt32LE((mode << 16) >>> 0, 38);
      central.writeUInt32LE(offset, 42);
      directory.push(central, filename);
      offset += local.length + filename.length + data.length;
    }
    const index = Buffer.concat(directory);
    const end = Buffer.alloc(22);
    end.writeUInt32LE(0x06054B50, 0);
    end.writeUInt16LE(entries.length, 8);
    end.writeUInt16LE(entries.length, 10);
    end.writeUInt32LE(index.length, 12);
    end.writeUInt32LE(offset, 16);
    return Buffer.concat([...contents, index, end]);
  };
  assert.equal(verifyArchive(makeZip(fixture())).group, group);
  for (const options of [{ widgetID: 'wrong.widget' }, { infoGroup: 'group.wrong' }, { platform: 7 }, { signedGroup: 'group.wrong' }, { adHoc: false }]) {
    assert.throws(() => verifyArchive(makeZip(fixture(options))));
  }
  const missingWidget = fixture().filter(entry => !entry.name.startsWith(WIDGET));
  assert.throws(() => verifyArchive(makeZip(missingWidget)));
  const unexecutable = fixture();
  unexecutable[2].mode = 0o100644;
  assert.throws(() => verifyArchive(makeZip(unexecutable)));
  assert.throws(() => verifyArchive(makeZip([...fixture(), { name: 'Payload/../escape', data: Buffer.from('x') }])));
  const damaged = makeZip(fixture());
  damaged[30 + Buffer.byteLength(APP + 'Info.plist')] ^= 1;
  assert.throws(() => verifyArchive(damaged));
  console.log('IPA verifier: 10 structural self-tests passed (fixtures only).');
}

try {
  const arguments_ = process.argv.slice(2);
  if (arguments_.length === 1 && arguments_[0] === '--self-test') {
    selfTest();
  } else {
    ensure(arguments_.length === 1, 'Usage: node scripts/verify-ipa.mjs <Datenblick.ipa> | --self-test');
    ensure(fs.statSync(arguments_[0]).size <= MAX_ARCHIVE_BYTES, 'IPA exceeds the 64 MiB artifact limit.');
    const result = verifyArchive(fs.readFileSync(arguments_[0]));
    console.log(`IPA structure verified: ${result.appID}, arm64 iOS app + WidgetKit extension, matching ad-hoc App Group entitlements (${result.entries} entries).`);
    console.log('The IPA requires local Apple ID re-signing before installation.');
  }
} catch (error) {
  console.error('IPA verification failed:', error.message);
  process.exitCode = 1;
}
