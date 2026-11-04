import { createServer } from 'node:http';

const escapeHtml = (value) => value.replace(/[&<>"']/g, (character) => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
})[character]);

const version = escapeHtml(process.env.APP_VERSION || 'unknown');
const storage = process.env.STORAGE_BLOB_ENDPOINT ? 'Configured' : 'Not set up yet';
const keyVault = process.env.KEYVAULT_URI ? 'Configured' : 'Not set up yet';
const legacyStorage = process.env.LEGACY_STORAGE_NAME ? 'Configured (legacy)' : 'Retired';
const page = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta http-equiv="refresh" content="10">
  <title>Contoso Orders ${version}</title>
</head>
<body>
  <h1>Contoso Orders ${version}</h1>
  <dl>
    <dt>Storage</dt><dd>${storage}</dd>
    <dt>Key Vault</dt><dd>${keyVault}</dd>
    <dt>Legacy storage</dt><dd>${legacyStorage}</dd>
  </dl>
  <p>Configuration status only; connectivity and permissions are not checked.</p>
</body>
</html>`;

createServer((request, response) => {
  if (request.url !== '/') {
    response.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    response.end('Not found');
    return;
  }
  response.writeHead(200, {
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': 'no-store',
    'Content-Security-Policy': "default-src 'none'; base-uri 'none'; frame-ancestors 'none'",
    'X-Content-Type-Options': 'nosniff',
  });
  response.end(page);
}).listen(80, '0.0.0.0');
