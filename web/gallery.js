import { loadScene } from "./runtime/contract.js";

async function loadGallery() {
  const response = await fetch(new URL("../glsl/index.json", import.meta.url));
  if (!response.ok) throw new Error(`Unable to load gallery: HTTP ${response.status}`);
  const ids = await response.json();
  if (!Array.isArray(ids) || new Set(ids).size !== ids.length
      || !ids.every(id => typeof id === "string" && /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(id))) {
    throw new Error("Invalid scene registry.");
  }
  const scenes = await Promise.all(ids.map(id => loadScene(new URL(`../glsl/${id}/scene.json`, import.meta.url))));
  for (const [index, scene] of scenes.entries()) {
    if (scene.id !== ids[index]) throw new Error("Scene id does not match its registry entry.");
    const card = document.createElement("article");
    card.className = "card";
    const preview = document.createElement("a");
    preview.className = "preview";
    preview.href = `demos/${scene.id}/`;
    preview.setAttribute("aria-label", `Open ${scene.title}`);
    const image = document.createElement("img");
    image.src = `assets/${scene.id}.jpg`;
    image.alt = scene.title;
    image.width = 1280;
    image.height = 800;
    preview.append(image);
    const details = document.createElement("div");
    details.className = "details";
    const tags = document.createElement("span");
    tags.className = "tags";
    tags.textContent = scene.tags.join(" / ");
    const title = document.createElement("h2");
    title.textContent = scene.title;
    const description = document.createElement("p");
    description.textContent = scene.description;
    const links = document.createElement("div");
    links.className = "links";
    const open = document.createElement("a");
    open.href = preview.href;
    open.textContent = "Open study ↗";
    const source = document.createElement("a");
    source.href = `../glsl/${scene.id}/${scene.source}`;
    source.download = `${scene.id}.glsl`;
    source.textContent = "Download GLSL ↓";
    links.append(open, source);
    details.append(tags, title, description, links);
    card.append(preview, details);
    document.querySelector("#scenes").append(card);
  }
}
loadGallery().catch(error => {
  console.error(error);
  const panel = document.querySelector("#error");
  panel.textContent = error.message;
  panel.hidden = false;
});
