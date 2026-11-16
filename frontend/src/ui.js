export const esc = (value) => String(value ?? "").replace(/[&<>"']/g, (character) => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
})[character]);

const paths = {
  orbit: '<circle cx="12" cy="12" r="3"/><ellipse cx="12" cy="12" rx="10" ry="5.5" transform="rotate(-42 12 12)"/>',
  grid: '<rect x="3" y="3" width="7" height="7" rx="2"/><rect x="14" y="3" width="7" height="7" rx="2"/><rect x="3" y="14" width="7" height="7" rx="2"/><rect x="14" y="14" width="7" height="7" rx="2"/>',
  people: '<path d="M12 20S4 15.6 4 9.7a4.3 4.3 0 0 1 8-2.1 4.3 4.3 0 0 1 8 2.1C20 15.6 12 20 12 20Z"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v3m0 14v3M2 12h3m14 0h3M5 5l2 2m10 10 2 2M5 19l2-2M17 7l2-2"/>',
  sparkles: '<path d="M10 3 12.1 8.9 18 11l-5.9 2.1L10 19l-2.1-5.9L2 11l5.9-2.1L10 3Zm9 11v6m-3-3h6M18 2v5m-2.5-2.5h5"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2m-8 3 1-1"/>',
  diamond: '<path d="m12 2.8 8.5 9.2-8.5 9.2L3.5 12 12 2.8Z"/><path d="m9 12 2 2 4-4"/>',
  planet: '<circle cx="12" cy="12" r="6"/><path d="M7 5C4 6 1.8 11 4.5 14.5c3 3.8 9.8 3 14.5.3 4-2.4 3.5-5.5.7-6.3"/>',
  food: '<path d="M5 3v6a3 3 0 0 0 6 0V3M8 3v18m9 0V3c-3 2-4 6-4 9h4"/>',
  calendar: '<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M3 10h18M8 3v4m8-4v4m-7 8h6"/>',
  chat: '<path d="M5 5h14a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H9l-5 3v-9a2 2 0 0 1-1-1.7V7a2 2 0 0 1 2-2Z"/><path d="M8 10h8m-8 3h5"/>',
  image: '<rect x="3" y="4" width="18" height="16" rx="3"/><circle cx="9" cy="9" r="1.3"/><path d="m4 18 5-5 3 3 4-5 4 5"/>',
  game: '<path d="M8 7h8c3 0 4 1.3 5 5.5.8 4-1 6.2-3 4.5l-3-2H9l-3 2c-2 1.7-3.8-.5-3-4.5C4 8.3 5 7 8 7Z"/><path d="M8 10v4m-2-2h4m5-1h.1m3 2h.1"/>',
  gift: '<rect x="3" y="8" width="18" height="4" rx="1"/><path d="M5 12v8h14v-8M12 8v12m0-12c-5 0-7-2-5-4 1.5-1.5 4 .3 5 4Zm0 0c5 0 7-2 5-4-1.5-1.5-4 .3-5 4Z"/>',
  compass: '<circle cx="12" cy="12" r="9"/><path d="m15.8 8.2-2 5.6-5.6 2 2-5.6 5.6-2Z"/>',
  chevron: '<path d="m9 6 6 6-6 6"/>',
  down: '<path d="m6 9 6 6 6-6"/>',
  back: '<path d="m15 6-6 6 6 6"/>',
  arrow: '<path d="M5 12h14m-6-6 6 6-6 6"/>',
  send: '<path d="M12 19V5m-6 6 6-6 6 6"/>',
  edit: '<path d="m14 5 5 5M4 20l5-1L20 8a2.8 2.8 0 0 0-4-4L5 15l-1 5Z"/>',
  close: '<path d="m6 6 12 12M18 6 6 18"/>',
  check: '<path d="m5 12 4 4L19 6"/>',
};

export const icon = (name) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths[name] ?? ""}</svg>`;

export function moduleUrl(id, draftId = "", edit = false, version = "") {
  const route = id === "universe" ? "/universe" : "/modules/" + id;
  const query = new URLSearchParams();
  if (draftId) query.set("draft", draftId);
  else if (version) query.set("version", version);
  return "#" + route + (edit ? "/edit" : "") + (query.size ? "?" + query : "");
}

export function header(title, back) {
  return `<header class="page-header">
    <a class="icon-button" href="${back}" aria-label="返回">${icon("back")}</a>
    <h1 tabindex="-1">${esc(title)}</h1>
    <span aria-hidden="true"></span>
  </header>`;
}

export function moduleBadge(module) {
  return `<span class="module-badge tone-${module.color}">${icon(module.icon)}</span>`;
}

export function actorButton(actor) {
  return `<button type="button" class="actor-button" data-action="choose-actor" aria-label="切换演示账号，当前 ${actor.toUpperCase()}">
    <span class="avatar avatar-${actor}">${actor.toUpperCase()}</span>${icon("down")}
  </button>`;
}
