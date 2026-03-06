import test from "node:test";
import assert from "node:assert/strict";
import { getServiceStatus } from "../src/services/exampleService.js";

test("service status", () => {
  assert.equal(getServiceStatus().status, "ok");
});
