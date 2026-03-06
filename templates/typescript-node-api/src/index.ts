import express from "express";
import { apiRouter } from "./routes/api.js";

const app = express();
const port = Number(process.env.PORT ?? 3000);

app.use(express.json());
app.use("/api", apiRouter);

app.get("/", (_, res) => {
  res.json({ project: "{{project_name}}", status: "running" });
});

app.listen(port, () => {
  console.log(`listening on ${port}`);
});
