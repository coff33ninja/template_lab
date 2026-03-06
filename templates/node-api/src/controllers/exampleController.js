import { getServiceStatus } from "../services/exampleService.js";

export function getHealth(_, res) {
  res.json(getServiceStatus());
}
