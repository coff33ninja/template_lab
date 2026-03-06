import { Router } from "express";
import { getHealth } from "../controllers/exampleController.js";

const router = Router();

router.get("/health", getHealth);

export { router as apiRouter };
