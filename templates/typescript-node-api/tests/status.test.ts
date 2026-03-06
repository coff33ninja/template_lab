import test from "node:test";
import assert from "node:assert/strict";
import { getStatus } from "../src/services/statusService.js";

test("status returns ok", () => {
  assert.equal(getStatus().status, "ok");
});
