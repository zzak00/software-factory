import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, readdir } from "node:fs/promises";
import { join, relative } from "node:path";
import test from "node:test";
import { HtmlValidate } from "html-validate";
import YAML from "yaml";

const root = new URL("../", import.meta.url);

async function filesBelow(directory) {
  const found = [];
  async function visit(current) {
    for (const entry of await readdir(current, { withFileTypes: true })) {
      const path = join(current, entry.name);
      if (entry.isDirectory()) await visit(path);
      else found.push(relative(root.pathname, path));
    }
  }
  await visit(new URL(directory, root).pathname);
  return found.sort();
}

test("the locked skill bundle is complete and exact", async () => {
  const lock = YAML.parse(await readFile(new URL("skills.lock", root), "utf8"));
  const locked = lock.files.map((entry) => entry.path).sort();
  assert.deepEqual(locked, await filesBelow("skills/"));

  for (const entry of lock.files) {
    const content = await readFile(new URL(entry.path, root));
    const digest = createHash("sha256").update(content).digest("hex");
    assert.equal(digest, entry.sha256, entry.path);
  }
});

test("skill metadata is valid and reusable skills stay workflow-agnostic", async () => {
  const skillFiles = (await filesBelow("skills/")).filter((path) => path.endsWith("/SKILL.md"));
  for (const path of skillFiles) {
    const content = await readFile(new URL(path, root), "utf8");
    const match = content.match(/^---\n([\s\S]*?)\n---\n/);
    assert.ok(match, `${path}: missing frontmatter`);
    const metadata = YAML.parse(match[1]);
    assert.equal(typeof metadata.name, "string", `${path}: name`);
    assert.equal(typeof metadata.description, "string", `${path}: description`);
  }

  const decoupled = ["to-spec", "to-tickets", "implement", "code-review", "plannotator-review"];
  const forbidden = /Spec Ready|Ready for Agent|factory:spec|issues\/<number>|Project item remains|isolated worktree/i;
  for (const name of decoupled) {
    const content = await readFile(new URL(`skills/${name}/SKILL.md`, root), "utf8");
    assert.doesNotMatch(content, forbidden, name);
  }
});

test("the mental map is valid standalone HTML", async () => {
  const path = new URL("software-factory-mental-map.html", root);
  const source = await readFile(path, "utf8");
  const report = await new HtmlValidate({ extends: ["html-validate:recommended"] }).validateString(source);
  assert.equal(report.valid, true, report.results.flatMap((result) => result.messages).map((message) => `${message.line}:${message.column} ${message.message}`).join("\n"));
  assert.match(source, /Clarify/);
  assert.match(source, /Prepare/);
  assert.match(source, /Implement/);
  assert.match(source, /Review/);
  assert.match(source, /Integrate/);
  assert.match(source, /Maintain/);
});
