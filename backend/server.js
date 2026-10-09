const { createApp } = require("./api/index");
const { verifyToken } = require("./api/middleware/auth");
const { addWsClient, removeWsClient } = require("./api/lib/broadcast");

let WebSocketPkg;
try {
  WebSocketPkg = require("ws");
} catch (e) {
  WebSocketPkg = null;
}

function createServerWithWs(expressApp) {
  const http = require("http");
  const server = http.createServer(expressApp);

  if (WebSocketPkg) {
    const wss = new WebSocketPkg.Server({ noServer: true });

    server.on("upgrade", async (request, socket, head) => {
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
      if (ws.ownerId) {
        addWsClient(ws.ownerId, ws);
        ws.send(JSON.stringify({ type: "connected", transport: "websocket", ownerId: ws.ownerId }));
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
