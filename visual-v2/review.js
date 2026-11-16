import { directions, pages } from "./content.js";

const key = "couple-visual-v2-review";
let marks = {};
try {
  const saved = JSON.parse(localStorage.getItem(key));
  marks = Object.fromEntries(Object.keys(directions).map((id) => {
    const record = saved?.[id];
    return [id, { favorite: record?.favorite === true, rating: [1, 2, 3, 4, 5].includes(record?.rating) ? record.rating : 0 }];
  }));
} catch {}
let direction = "a";
let page = "home";
let comparing = false;
let shown = "";
const find = (selector) => document.querySelector(selector);

function current() {
  return marks[direction] ?? { favorite: false, rating: 0 };
}

function save(update) {
  marks[direction] = { ...current(), ...update };
  try {
    localStorage.setItem(key, JSON.stringify(marks));
    find("#feedback").textContent = "已记录在此浏览器";
  } catch {
    find("#feedback").textContent = "浏览器存储不可用，记录在本次打开期间有效";
  }
  render();
}

function url(id, view) { return "sample.html?direction=" + id + "&view=" + view; }

function render() {
  const size = Number(find("#size").value);
  const height = size === 360 ? 800 : 844;
  find("#directions").innerHTML = Object.entries(directions).map(([id, item]) => {
    const mark = marks[id];
    return `<button type="button" data-direction="${id}" aria-pressed="${direction === id}">
      <b>${id.toUpperCase()} · ${item.name}</b><small>${item.note}</small>
      ${mark?.favorite || mark?.rating ? `<small>${mark.favorite ? "已收藏 " : ""}${mark.rating ? mark.rating + " / 5" : ""}</small>` : ""}
    </button>`;
  }).join("");
  find("#pages").innerHTML = Object.entries(pages).map(([id, label]) => `<button type="button" data-page="${id}" aria-pressed="${id === page}">${label}</button>`).join("");
  find("#favorite").textContent = current().favorite ? "已收藏" : "收藏";
  find("#favorite").setAttribute("aria-pressed", current().favorite);
  find("#rating").value = String(current().rating);
  find("#compare").setAttribute("aria-pressed", comparing);
  find("#compare").textContent = comparing ? "返回实机比例预览" : "并排比较";
  find("#direct").href = url(direction, page);
  const preview = find("#single");
  preview.hidden = comparing;
  const imageFolder = size + "x" + height;
  preview.style.setProperty("--w", size + "px");
  preview.style.setProperty("--h", height + "px");
  const requested = url(direction, page);
  if (!comparing && shown !== requested) {
    find("#phone").src = requested;
    find("#phone").title = directions[direction].name + " · " + pages[page];
    shown = requested;
  }
  const comparisons = find("#comparisons");
  comparisons.hidden = !comparing;
  comparisons.innerHTML = comparing ? Object.entries(directions).map(([id, item]) => `<figure>
    <figcaption>${id.toUpperCase()} · ${item.name}</figcaption>
    <img src="evidence/${imageFolder}/${id}-${page}.webp" alt="${item.name}的${pages[page]}" width="${size}" height="${height}">
    <button type="button" data-open="${id}">体验${item.name}</button>
  </figure>`).join("") : "";
}

document.addEventListener("click", (event) => {
  const target = event.target.closest("button");
  if (!target) return;
  if (target.id === "favorite") return save({ favorite: !current().favorite });
  if (target.id === "compare") comparing = !comparing;
  if (target.dataset.direction) direction = target.dataset.direction;
  if (target.dataset.page) page = target.dataset.page;
  if (target.dataset.open) { direction = target.dataset.open; comparing = false; shown = ""; }
  render();
  if (target.dataset.direction) find('[data-direction="' + direction + '"]').focus();
  if (target.dataset.page) find('[data-page="' + page + '"]').focus();
});
find("#rating").addEventListener("change", (event) => save({ rating: Number(event.target.value) }));
find("#size").addEventListener("change", render);
window.addEventListener("message", (event) => {
  const data = event.data;
  if (event.origin !== location.origin || event.source !== find("#phone").contentWindow ||
      data?.type !== "visual-page" || data.direction !== direction || !Object.hasOwn(pages, data.page)) return;
  if (page === data.page) return;
  page = data.page;
  shown = url(direction, page);
  render();
});

render();
