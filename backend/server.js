const { createApp } = require("./api/index");
const { verifyToken } = require("./api/middleware/auth");
const { addWsClient, removeWsClient } = require("./api/lib/broadcast");

let WebSocketPkg;
try {
  WebSocketPkg = require("ws");
} catch (e) {
  WebSocketPkg = null;
}

// Clients only send small {type:"auth"|"ping"} frames.
const WS_MAX_PAYLOAD_BYTES = 4096;
const WS_AUTH_TIMEOUT_MS = 5000;
const WS_HEARTBEAT_MS = 30000;

function createServerWithWs(expressApp) {
  const http = require("http");
  const server = http.createServer(expressApp);

  if (WebSocketPkg) {
    const wss = new WebSocketPkg.Server({ noServer: true, maxPayload: WS_MAX_PAYLOAD_BYTES });

    // Drop sockets that stop answering pings so they leave the broadcast registry.
    const heartbeat = setInterval(() => {
      for (const ws of wss.clients) {
        if (ws.isAlive === false) {
          ws.terminate();
          continue;
        }
        ws.isAlive = false;
        ws.ping();
      }
    }, WS_HEARTBEAT_MS);
    heartbeat.unref();
    wss.on("close", () => clearInterval(heartbeat));

    server.on("upgrade", async (request, socket, head) => {
      // No listener is attached while the token is verified; an error then
      // would otherwise crash the process.
      const onEarlySocketError = () => socket.destroy();
      socket.on("error", onEarlySocketError);
      try {
        const urlObj = new URL(request.url, `http://${request.headers.host || "localhost"}`);
        if (urlObj.pathname === "/ws" || urlObj.pathname === "/api/ws") {
          const token = urlObj.searchParams.get("token");
          let ownerId = null;
          if (token) {
            try {
              const decoded = await verifyToken(token);
              if (decoded) ownerId = decoded.uid;
            } catch (e) {}
          }
          socket.removeListener("error", onEarlySocketError);
          wss.handleUpgrade(request, socket, head, (ws) => {
            ws.ownerId = ownerId;
            wss.emit("connection", ws, request);
          });
        } else {
          socket.destroy();
        }
      } catch (err) {
        socket.destroy();
      }
    });

    wss.on("connection", (ws) => {
      ws.isAlive = true;
      ws.on("pong", () => {
        ws.isAlive = true;
      });
      // Without this listener a malformed or oversized frame crashes Node.
      ws.on("error", (err) => {
        console.warn("WebSocket error:", err.message);
        ws.terminate();
      });

      if (ws.ownerId) {
        addWsClient(ws.ownerId, ws);
        ws.send(JSON.stringify({ type: "connected", transport: "websocket", ownerId: ws.ownerId }));
      } else {
        const authTimer = setTimeout(() => {
          if (!ws.ownerId) ws.close(1008, "Authentication required");
        }, WS_AUTH_TIMEOUT_MS);
        ws.once("close", () => clearTimeout(authTimer));
      }

      ws.on("message", async (msg) => {
        try {
          const data = JSON.parse(msg.toString());
          if (data.type === "auth" && data.token) {
            const decoded = await verifyToken(data.token);
            if (decoded) {
              if (ws.ownerId) {
                removeWsClient(ws.ownerId, ws);
              }
              ws.ownerId = decoded.uid;
              addWsClient(ws.ownerId, ws);
              ws.send(JSON.stringify({ type: "authenticated", transport: "websocket", ownerId: ws.ownerId }));
            }
          } else if (data.type === "ping") {
            ws.send(JSON.stringify({ type: "pong" }));
          }
        } catch (e) {}
      });

      ws.on("close", () => {
        if (ws.ownerId) {
          removeWsClient(ws.ownerId, ws);
        }
      });
    });
  }

  return server;
}

const PORT = process.env.PORT || 3000;
const app = createApp();
const server = createServerWithWs(app);

server.listen(PORT, () => {
  console.log(`Unmurce backend & live WebSocket server listening on port ${PORT}`);
});

module.exports = { createApp, createServerWithWs };
