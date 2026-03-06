import express from "express";

const app = express();
const port = 3001;

app.get("/health", (_, res) => res.json({ status: "ok" }));

app.listen(port, () => {
  console.log(`api on ${port}`);
});
