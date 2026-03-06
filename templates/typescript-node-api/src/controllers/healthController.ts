import type { Request, Response } from "express";
import { getStatus } from "../services/statusService.js";

export function getHealth(_: Request, res: Response): void {
  res.json(getStatus());
}
