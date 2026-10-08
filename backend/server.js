const app = require("./api/index");
const { createServerWithWs } = app;

const PORT = process.env.PORT || 3000;
const server = createServerWithWs(app);
server.listen(PORT, () => {
  console.log(`Unmurce backend & live WebSocket server listening on port ${PORT}`);
});
