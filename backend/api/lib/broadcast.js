const wsClientsByOwner = new Map();
const sseClientsByOwner = new Map();

function addWsClient(ownerId, ws) {
  if (!ownerId) return;
  if (!wsClientsByOwner.has(ownerId)) {
    wsClientsByOwner.set(ownerId, new Set());
  }
  wsClientsByOwner.get(ownerId).add(ws);
}

function removeWsClient(ownerId, ws) {
  if (!ownerId || !wsClientsByOwner.has(ownerId)) return;
  wsClientsByOwner.get(ownerId).delete(ws);
  if (wsClientsByOwner.get(ownerId).size === 0) {
    wsClientsByOwner.delete(ownerId);
  }
}

function addSseClient(ownerId, res) {
  if (!ownerId) return;
  if (!sseClientsByOwner.has(ownerId)) {
    sseClientsByOwner.set(ownerId, new Set());
  }
  sseClientsByOwner.get(ownerId).add(res);
}

function removeSseClient(ownerId, res) {
  if (!ownerId || !sseClientsByOwner.has(ownerId)) return;
  sseClientsByOwner.get(ownerId).delete(res);
  if (sseClientsByOwner.get(ownerId).size === 0) {
    sseClientsByOwner.delete(ownerId);
  }
}

function broadcastLiveChange(ownerId, data) {
  if (!ownerId) return;
  const payloadStr = JSON.stringify(data);

  // WebSocket clients
  const wsSet = wsClientsByOwner.get(ownerId);
  if (wsSet) {
    for (const ws of wsSet) {
      if (ws.readyState === 1 /* OPEN */) {
        try { ws.send(payloadStr); } catch (e) {}
      }
    }
  }

  // SSE clients
  const sseSet = sseClientsByOwner.get(ownerId);
  if (sseSet) {
    const sseMsg = `data: ${payloadStr}\n\n`;
    for (const clientRes of sseSet) {
      try { clientRes.write(sseMsg); } catch (e) {}
    }
  }
}

function cleanupSseClient(res) {
  for (const [, clients] of sseClientsByOwner) {
    clients.delete(res);
  }
}

module.exports = {
  addWsClient,
  removeWsClient,
  addSseClient,
  removeSseClient,
  broadcastLiveChange,
  cleanupSseClient,
};
