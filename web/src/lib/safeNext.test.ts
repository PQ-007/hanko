import { test } from "node:test";
import assert from "node:assert/strict";
import { safeNext } from "./safeNext.ts";

test("same-site paths pass through, query included", () => {
  assert.equal(safeNext("/share/e954c900a22748f0921271419c853e80"), "/share/e954c900a22748f0921271419c853e80");
  assert.equal(safeNext("/decks?deck=abc"), "/decks?deck=abc");
});

test("anything that could leave the site falls back", () => {
  for (const bad of ["@evil.example", "//evil.example", "/\\evil.example", "https://evil.example", "evil", "/\\/evil", "/ok\u0000", "javascript:alert(1)"]) {
    assert.equal(safeNext(bad), "/decks", bad);
  }
});

test("missing means the default", () => {
  assert.equal(safeNext(null), "/decks");
  assert.equal(safeNext("", "/x"), "/x");
});
