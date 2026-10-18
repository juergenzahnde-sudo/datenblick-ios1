// Structural checks usable on Windows. This does not replace an Xcode build.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const text = fs.readFileSync(path.join(root, 'Datenblick.xcodeproj/project.pbxproj'), 'utf8');
const tokens = [...text.matchAll(/\/\*[\s\S]*?\*\/|\/\/[^\n]*|"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+/g)]
  .map(match => match[0]).filter(token => !token.startsWith('//') && !token.startsWith('/*'));
let cursor = 0;
const take = expected => { const token = tokens[cursor++]; if (expected) assert.equal(token, expected); return token; };
const scalar = () => { const token = take(); assert.ok(token !== undefined, 'Unexpected end of project'); return token.startsWith('"') ? JSON.parse(token) : token; };
const value = () => {
  if (tokens[cursor] === '{') {
    take('{'); const result = {};
    while (tokens[cursor] !== '}') {
      const key = scalar(); assert.ok(!Object.hasOwn(result, key), `Duplicate key ${key}`);
      take('='); result[key] = value(); take(';');
    }
    take('}'); return result;
  }
  if (tokens[cursor] === '(') {
    take('('); const result = [];
    while (tokens[cursor] !== ')') { result.push(value()); if (tokens[cursor] !== ')') take(','); }
    take(')'); return result;
  }
  return scalar();
};
const project = value();
assert.equal(cursor, tokens.length, 'Trailing tokens');
const objects = project.objects;
assert.ok(objects[project.rootObject]?.isa === 'PBXProject', 'Invalid root');
const visit = obj => {
  if (typeof obj === 'string' && /^[A-F0-9]{24}$/.test(obj)) assert.ok(objects[obj], `Unresolved reference ${obj}`);
  else if (Array.isArray(obj)) obj.forEach(visit);
  else if (obj && typeof obj === 'object') Object.values(obj).forEach(visit);
};
Object.values(objects).forEach(visit);
for (const obj of Object.values(objects)) {
  if (obj.isa === 'PBXFileReference' && obj.sourceTree === '<group>') {
    assert.ok(fs.existsSync(path.join(root, obj.path)), `Missing file ${obj.path}`);
  }
}
const targets = Object.values(objects).filter(obj => obj.isa === 'PBXNativeTarget');
assert.equal(targets.length, 2);
for (const target of targets) {
  const phases = target.buildPhases.map(ref => objects[ref]);
  const sources = phases.find(phase => phase.isa === 'PBXSourcesBuildPhase').files
    .map(ref => objects[objects[ref].fileRef].path);
  const expectedFolder = target.name === 'Datenblick' ? 'App' : 'Widgets';
  const expected = ['Shared', expectedFolder].flatMap(folder => fs.readdirSync(path.join(root, folder))
    .filter(file => file.endsWith('.swift')).map(file => `${folder}/${file}`));
  assert.deepEqual([...sources].sort(), expected.sort(), `Target source membership: ${target.name}`);
  assert.equal(sources.filter(file => /@main\b/.test(fs.readFileSync(path.join(root, file), 'utf8'))).length, 1);
  const resources = phases.find(phase => phase.isa === 'PBXResourcesBuildPhase').files
    .map(ref => objects[objects[ref].fileRef].path);
  assert.ok(resources.includes('Config/PrivacyInfo.xcprivacy'));
}
const app = targets.find(target => target.name === 'Datenblick');
assert.ok(app.buildPhases.map(ref => objects[ref]).some(phase => phase.isa === 'PBXCopyFilesBuildPhase' && phase.dstSubfolderSpec === '13'));
assert.equal(app.dependencies.length, 1, 'App must build its extension');
assert.equal(targets.find(target => target.name === 'DatenblickWidget').dependencies.length, 0);
const icon = fs.readFileSync(path.join(root, 'Assets.xcassets/AppIcon.appiconset/AppIcon.png'));
assert.equal(icon.readUInt32BE(16), 1024); assert.equal(icon.readUInt32BE(20), 1024);
assert.equal(icon[25], 2, 'App icon should be opaque RGB');
console.log(`Structural checks passed: ${Object.keys(objects).length} project objects, 2 targets, complete source membership, embedded widget, privacy resources, opaque 1024px icon.`);
console.log('Native Swift compilation, unit tests and device QA still require macOS/Xcode.');
