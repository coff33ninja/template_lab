import test from "node:test";
import assert from "node:assert/strict";
import { createGreeting } from "../dist/index.js";

test("createGreeting", () => {
  assert.match(createGreeting("dev"), /{{project_slug}}/);
});
