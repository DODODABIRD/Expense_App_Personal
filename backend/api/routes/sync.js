const db = require("../db");

/**
 * POST /api/sync/beat
 * Records the last successful sync timestamp for a device owned by the caller.
 */
async function deviceSyncBeat(req, res) {
  const deviceId = String(req.body?.deviceId || "").trim();
  if (!deviceId) {
    return res.status(400).json({ error: "deviceId is required" });
  }

  try {
    await db.connectDB();
    const row = await db.upsertDeviceSync(req.user.uid, {
      deviceId,
      deviceName: req.body?.deviceName,
      platform: req.body?.platform,
      appVersion: req.body?.appVersion,
      expenseCount: req.body?.expenseCount,
    });
    res.json({ success: true, lastSyncAt: row?.last_sync_at || new Date() });
  } catch (err) {
    console.error("Device sync beat failed:", err);
    res.status(500).json({ error: "Could not record device sync" });
  }
}

module.exports = { deviceSyncBeat };
