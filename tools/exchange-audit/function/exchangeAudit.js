const { app } = require('@azure/functions');
const { BlobServiceClient } = require('@azure/storage-blob');
const { DefaultAzureCredential } = require('@azure/identity');

const ACCOUNT   = 'pcorpsambcleanupazuc01';
const CONTAINER = 'exchange-audit';
const BLOB      = 'exchange-audit.json';

// Auth is enforced by App Service Easy Auth at the platform layer (unauthenticated
// requests never reach here), so the function itself is authLevel 'anonymous'.
app.http('exchange-audit', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'exchange-audit',
  handler: async (request, context) => {
    try {
      const svc  = new BlobServiceClient(`https://${ACCOUNT}.blob.core.windows.net`, new DefaultAzureCredential());
      const blob = svc.getContainerClient(CONTAINER).getBlobClient(BLOB);
      const dl   = await blob.download();
      const body = await streamToString(dl.readableStreamBody);
      return { status: 200, headers: { 'Content-Type': 'application/json' }, body };
    } catch (e) {
      context.error('exchange-audit blob read failed', e);
      return { status: 502, jsonBody: { error: 'Could not read audit data from storage.' } };
    }
  }
});

async function streamToString(stream) {
  const chunks = [];
  for await (const chunk of stream) chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  return Buffer.concat(chunks).toString('utf8');
}
