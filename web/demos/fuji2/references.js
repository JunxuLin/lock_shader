export function timeBand(hour) {
  const time = hour % 24;
  return time < 5 || time >= 20 ? "night" : time < 10 ? "morning" : time < 16 ? "day" : "evening";
}

export function evidenceFor(state, items) {
  const requested = { seasons: state.season, weather: state.weather, times: timeBand(state.timeOfDay) };
  const related = items.filter(item => Object.entries(requested).some(([axis, value]) => item.covers[axis].includes(value)));
  const gaps = Object.entries(requested)
    .filter(([axis, value]) => !items.some(item => item.covers[axis].includes(value)))
    .map(([, value]) => value);
  return { related, gaps };
}

export async function mountReferences() {
  const response = await fetch(new URL("assets/references.json", import.meta.url));
  if (!response.ok) throw new Error(`Unable to load reference provenance: HTTP ${response.status}`);
  const catalog = await response.json();
  const gallery = document.querySelector("#reference-gallery");
  const cards = new Map();
  for (const item of catalog.items) {
    const card = document.createElement("figure");
    card.className = "reference-card";
    const image = document.createElement("img");
    image.src = new URL(`assets/references/${item.file}`, import.meta.url).href;
    image.alt = item.observations;
    image.loading = "lazy";
    const caption = document.createElement("figcaption");
    const title = document.createElement("h3");
    title.textContent = item.title;
    const credit = document.createElement("p");
    credit.textContent = `${item.author} · ${item.captured}`;
    const links = document.createElement("p");
    for (const [text, href] of [["Source", item.sourceUrl], [item.license, item.licenseUrl]]) {
      const link = document.createElement("a");
      link.href = href;
      link.target = "_blank";
      link.rel = "noreferrer";
      link.textContent = text;
      links.append(link, document.createTextNode(" "));
    }
    const notes = document.createElement("p");
    notes.textContent = item.observations;
    const limits = document.createElement("p");
    limits.className = "limitations";
    limits.textContent = item.limitations;
    caption.append(title, credit, links, notes, limits);
    card.append(image, caption);
    gallery.append(card);
    cards.set(item.id, card);
  }
  return state => {
    const { related, gaps } = evidenceFor(state, catalog.items);
    for (const item of catalog.items) cards.get(item.id).dataset.related = String(related.includes(item));
    const text = `${related.length} related ${related.length === 1 ? "photo" : "photos"}, not an exact-match verification. ${
      gaps.length ? `No direct reference for: ${gaps.join(", ")}; these conditions are inferred.`
        : "References cover individual aspects only; their combination is inferred."}`;
    const summary = document.querySelector("#evidence-summary");
    if (summary.textContent !== text) summary.textContent = text;
    const hour = String(Math.floor(state.timeOfDay)).padStart(2, "0");
    const minute = String(Math.round(state.timeOfDay % 1 * 60)).padStart(2, "0");
    document.querySelector("#reference-selection").textContent = `${state.season} / ${state.weather} / ${hour}:${minute} scene time. ${text}`;
  };
}
