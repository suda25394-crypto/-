import { directions, pages, features, zones, starting, world, director } from "./content.js";
import { esc } from "../frontend/src/ui.js";

const params = new URLSearchParams(location.search);
const direction = Object.hasOwn(directions, params.get("direction")) ? params.get("direction") : "a";
const initial = Object.hasOwn(pages, params.get("view")) ? params.get("view") : "home";
const app = document.querySelector("#app");
const nav = document.querySelector("#nav");
const overlay = document.querySelector("#overlay");
let view = initial;
let plan = starting;
let worldDraft = "";
let activePlace = 0;
let worldTab = "story";

const artwork = {
  a: { core: "蓝绿色透光玻璃折带组成的悬浮智能中枢", world: "两人站在透明穹顶和水边阶梯组成的观测站" },
  b: { core: "蓝色纸张与两人沿湖散步的照片拼贴", world: "以纸雕地图、两位角色和湖边观测站组成的印刷拼贴" },
  c: { core: "有两位角色、窗和中央暖灯的等距立体生活工作室", world: "两位角色站在湖边的紫蓝色等距观测站" },
};
const image = (kind) => `<img class="art" src="assets/${direction}-${kind}.webp" width="720" height="720" alt="${artwork[direction][kind]}">`;
const mark = (id) => `<i aria-hidden="true" class="mark ${features[id].shape}"></i>`;
const avatars = '<span class="avatars" aria-hidden="true"><i>澄</i><i>屿</i></span>';

function pair() {
  return `<button type="button" data-action="pair" class="pair" aria-label="查看双人档案">${avatars}<span>阿澄 &amp; 小屿</span></button>`;
}
function top(trail = "") {
  return `<header class="mast"><a href="#home" class="wordmark">我们之间</a>
    ${trail ? `<span>${trail}</span>` : pair()}</header>`;
}
function feature(id, cls = "") {
  const editorial = cls === "b-featured";
  const art = editorial ? image(id === "universe" ? "world" : "core") : "";
  const title = editorial ? `<small>${esc(features[id].title)}</small>` : "";
  const body = `${mark(id)}<span>${features[id].name}${title}</span>${art}`;
  return id === "universe"
    ? `<a href="#universe" class="feature ${cls}" data-module="${id}">${body}</a>`
    : `<button type="button" class="feature ${cls}" data-feature="${id}" data-module="${id}">${body}</button>`;
}
function resultActions() {
  return `<div class="recommendation" aria-label="AI 关联功能">${plan.ids.map((id) => feature(id)).join("")}</div>`;
}
const ask = (label = "告诉 AI 你的想法") => `<button type="button" class="ask" data-action="ask">${label}<span aria-hidden="true">↗</span></button>`;

function homeA() {
  return `<section class="home a-home">${top()}<div class="a-intro"><h1>周末，想怎么过？</h1></div>
    <div class="a-stage">${image("core")}<span class="a-system">小智 <i></i> AI 中枢</span>${ask()}</div>
    <div class="a-outputs"><p>${esc(plan.note)}</p>${resultActions()}</div>
  </section>`;
}
function homeB() {
  return `<section class="home b-home">${top()}
    <div class="b-spread"><div class="b-heading"><h1>周末，<br>想怎么过？</h1><small>小智 · AI 中枢</small></div>
    <figure>${image("core")}</figure></div>
    <div class="b-brief">${ask()}<p>${esc(plan.note)}</p>${resultActions()}</div>
  </section>`;
}
function homeC() {
  return `<section class="home c-home">${top()}<div class="c-room">${image("core")}
    <div class="c-title"><small>小智 · AI 中枢</small><h1>周末，想怎么过？</h1></div>
    <div class="c-pins">${resultActions()}</div>
    ${ask()}</div><p class="c-brief">${esc(plan.note)}</p>
  </section>`;
}

function directoryHead() {
  return `${top("功能目录")}<h1>十二项功能</h1><p class="lead">打开任一功能查看内容，也可以让 AI 一起安排。</p>`;
}
function modulesA() {
  return `<section class="directory a-directory">${directoryHead()}
    <div class="a-index">${zones.map((zone) => `<section class="a-rail"><h2>${zone.title}</h2>
      <div>${zone.ids.map((id) => feature(id)).join("")}</div></section>`).join("")}</div>
  </section>`;
}
function modulesB() {
  const bOrder = Object.keys(features);
  return `<section class="directory b-directory">${directoryHead()}
    <div class="b-index">${bOrder.map((id) => feature(id, ["date", "universe"].includes(id) ? "b-featured" : "b-piece")).join("")}</div>
  </section>`;
}
function modulesC() {
  return `<section class="directory c-directory">${directoryHead()}
    <div class="c-map"><figure class="c-map-print">${image("core")}</figure>${zones.map((zone) => `<section class="c-zone"><h2>${zone.title}</h2>
      <div>${zone.ids.map((id) => feature(id)).join("")}</div></section>`).join("")}</div>
  </section>`;
}

function story() {
  return `<section class="story"><h2>${world.chapter}</h2><p>${world.summary}</p>
    <div class="cast">${world.people.map(([name, bio]) => `<div><b>${name}</b><small>${bio}</small></div>`).join("")}</div>
    ${worldDraft ? `<p class="world-draft">AI 草案 · ${esc(worldDraft)}</p>` : ""}
  </section>`;
}
function worldTitle() {
  return `${top("独立小宇宙")}<h1>${world.name}</h1>`;
}
function placeButtons() {
  return world.places.map(([name], index) => `<button type="button" data-place="${index}" aria-pressed="${activePlace === index}">${name}</button>`).join("");
}
function universeA() {
  return `<section class="world a-world">${worldTitle()}
    <div class="a-world-optics">${image("world")}<div class="place-buttons">${placeButtons()}</div></div>
    <p class="place-note" aria-live="polite">${world.places[activePlace][1]}</p>${story()}${ask("和 AI 改写这个世界")}
  </section>`;
}
function universeB() {
  const isStory = worldTab === "story";
  return `<section class="world b-world">${worldTitle()}<figure>${image("world")}</figure>
    <div class="chapter-tabs" aria-label="探索小宇宙">
      <button type="button" data-world="story" aria-pressed="${isStory}">读故事</button>
      <button type="button" data-world="places" aria-pressed="${!isStory}">看场景</button>
    </div>
    ${isStory ? story() : `<div class="place-buttons">${placeButtons()}</div><p class="place-note" aria-live="polite">${world.places[activePlace][1]}</p>`}
    ${ask("和 AI 改写这个世界")}
  </section>`;
}
function universeC() {
  return `<section class="world c-world">${worldTitle()}
    <div class="c-world-map">${image("world")}<div class="place-buttons">${placeButtons()}</div></div>
    <p class="place-note" aria-live="polite">${world.places[activePlace][1]}</p>${story()}${ask("和 AI 改写这个世界")}
  </section>`;
}
const renderers = {
  a: { home: homeA, modules: modulesA, universe: universeA },
  b: { home: homeB, modules: modulesB, universe: universeB },
  c: { home: homeC, modules: modulesC, universe: universeC },
};

function render() {
  document.body.dataset.direction = direction;
  document.body.dataset.page = view;
  app.innerHTML = renderers[direction][view]();
  nav.innerHTML = [["home", "中枢", "◈"], ["modules", "功能", "⊞"], ["universe", "小宇宙", "✷"]].map(([id, label, symbol]) =>
    `<a href="#${id}" ${view === id ? 'aria-current="page"' : ""}><span aria-hidden="true">${symbol}</span>${label}</a>`).join("");
  if (window.parent !== window) window.parent.postMessage({ type: "visual-page", direction, page: view }, location.origin);
}

const dialogFrame = (title, body) => `<header><h2 id="dialog-title">${title}</h2><button type="button" data-action="close" aria-label="关闭">×</button></header>${body}`;
function openDialog(title, body) {
  overlay.innerHTML = dialogFrame(title, body);
  overlay.showModal();
}

function askBody() {
  const sample = view === "universe" ? "把观测站的窗灯点亮" : "周末想和女朋友出去玩";
  return `<form id="request">
    <p>本地模拟</p>
    <label for="idea">${view === "universe" ? "想改动哪里？" : "你们想做什么？"}</label>
    <input id="idea" name="idea" maxlength="150" placeholder="${sample}" required>
    <button type="button" class="text-button" data-action="example" data-text="${sample}">使用示例</button>
    <button type="submit" class="ask">看看 AI 怎么安排 <span aria-hidden="true">↗</span></button>
    <p role="status" id="input-status"></p>
  </form>`;
}

function reselect(selector) {
  render();
  app.querySelector(selector)?.focus();
}
document.addEventListener("click", (event) => {
  const button = event.target.closest("button");
  if (!button) return;
  if (button.dataset.feature) {
    const item = features[button.dataset.feature];
    if (overlay.open) overlay.close();
    openDialog(item.name, `<p><strong>${esc(item.title)}</strong></p><p>${esc(item.summary)}</p>
      <details><summary>查看详情</summary><p class="preline">${esc(item.details)}</p></details>`);
  } else if (button.dataset.place !== undefined) {
    activePlace = Number(button.dataset.place);
    reselect('[data-place="' + activePlace + '"]');
  } else if (button.dataset.world) {
    worldTab = button.dataset.world;
    reselect('[data-world="' + worldTab + '"]');
  } else if (button.dataset.action === "ask") {
    openDialog("和 AI 说说", askBody());
  } else if (button.dataset.action === "pair") {
    openDialog("我们的小档案", `<div class="cast">${world.people.map(([name, bio]) => `<div><b>${name}</b><small>${bio}</small></div>`).join("")}</div><p>示例档案</p>`);
  } else if (button.dataset.action === "example") {
    const input = overlay.querySelector("#idea");
    input.value = button.dataset.text;
    input.focus();
  } else if (button.dataset.action === "close") {
    overlay.close();
  }
});
overlay.addEventListener("click", (event) => {
  if (event.target.closest("a[href='#universe']")) overlay.close();
});
overlay.addEventListener("submit", (event) => {
  event.preventDefault();
  const input = new FormData(event.target).get("idea")?.trim();
  if (!input) { overlay.querySelector("#input-status").textContent = "请写一点具体的想法。"; return; }
  const next = director(input, view);
  if (view === "universe") { worldDraft = next.note; worldTab = "story"; }
  else plan = next;
  render();
  overlay.innerHTML = dialogFrame("AI 整理结果", `<p>本地模拟 · ${esc(next.note)}</p><div class="dialog-results">
    ${next.ids.map((id) => feature(id)).join("")}</div><button type="button" class="ask" data-action="close">返回查看 <span aria-hidden="true">↗</span></button>`);
  overlay.querySelector("[data-action=close]").focus();
});
window.addEventListener("hashchange", () => {
  const path = location.hash.slice(1);
  view = Object.hasOwn(pages, path) ? path : initial;
  if (overlay.open) overlay.close();
  render();
  window.scrollTo(0, 0);
});
const hash = location.hash.slice(1);
if (Object.hasOwn(pages, hash)) view = hash;
render();
