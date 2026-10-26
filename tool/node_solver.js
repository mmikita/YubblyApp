#!/usr/bin/env node
// CLI wrapper around the same yt-dlp/ejs solver bundled for the app WebView.
// Usage: node tool/node_solver.js <challenge> < player.js
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.join(__dirname, '..', 'assets', 'js');
const lib = fs.readFileSync(path.join(root, 'meriyah-astring.min.js'), 'utf8');
const core = fs.readFileSync(path.join(root, 'ejs-core.min.js'), 'utf8');
const location = {
  hash: '',
  host: 'www.youtube.com',
  hostname: 'www.youtube.com',
  href: 'https://www.youtube.com/watch?v=yt-dlp-wins',
  origin: 'https://www.youtube.com',
  password: '',
  pathname: '/watch',
  port: '',
  protocol: 'https:',
  search: '?v=yt-dlp-wins',
  username: '',
};
const sandbox = {
  console,
  document: {},
  navigator: {},
  location,
  XMLHttpRequest: { prototype: {} },
};
sandbox.window = sandbox;
sandbox.self = sandbox;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(lib, sandbox);
vm.runInContext('var meriyah=lib.meriyah, astring=lib.astring;', sandbox);
vm.runInContext(core, sandbox);

const player = fs.readFileSync(0, 'utf8');
const challenge = process.argv[2];
if (!challenge) {
  console.error('missing challenge');
  process.exit(2);
}
const result = sandbox.jsc({
  type: 'player',
  player,
  requests: [{ type: 'n', challenges: [challenge] }],
});
const response = result && result.responses && result.responses[0];
if (!response || response.type !== 'result' || !response.data[challenge]) {
  console.error(JSON.stringify(result));
  process.exit(1);
}
console.log(response.data[challenge]);
