import { cp, mkdir, rm } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const root = new URL("../", import.meta.url);
const output = new URL("_site/", root);
await rm(output, { recursive: true, force: true });
await mkdir(output, { recursive: true });
for (const path of ["index.html", "web", "glsl"]) {
  await cp(new URL(path, root), new URL(path, output), { recursive: true });
}
console.log(`Static site: ${fileURLToPath(output)}`);
