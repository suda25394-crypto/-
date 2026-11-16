import { modules } from "./data.js";
import { demo } from "./services.js";
import { chatPage, chooser, profileEditor, profilesPage } from "./people-view.js";
import { directory, home, moduleEditor, modulePage, nav, reviewBody } from "./modules-view.js";
import { header, moduleUrl } from "./ui.js";

const screen = document.querySelector("#screen");
const navigation = document.querySelector("#navigation");
const dialog = document.querySelector("#review");
const status = document.querySelector("#status");
let current;
let pending;
let toastTimer;

function route() {
  const hash = location.hash.slice(1) || "/";
  const [name, rawQuery] = hash.split("?", 2);
  const query = new URLSearchParams(rawQuery);
  const segments = name.split("/").filter(Boolean);
  const [group, second, third] = segments;
  if (!segments.length) return { page: "home", nav: "/" };
  if (group === "modules" && !second) return { page: "directory", nav: "/modules" };
  if (group === "universe" || group === "modules" && Object.hasOwn(modules, second)) {
    return {
      page: "module", id: group === "universe" ? "universe" : second,
      edit: (group === "universe" ? second : third) === "edit",
      draftId: query.get("draft") || "", version: query.get("version") === "shared" ? "shared" : "",
    };
  }
  if (group === "chat" && ["personal", "shared"].includes(second)) {
    const id = query.get("module");
    return { page: "chat", space: second, moduleId: Object.hasOwn(modules, id) ? id : "" };
  }
  if (group === "profiles" && (!second || ["a", "b"].includes(second))) {
    const actor = demo.session().actor;
    const owner = second || actor;
    const edit = third === "edit" && owner === actor;
    return { page: "profiles", owner, edit, nav: edit ? "" : "/profiles" };
  }
  return { page: "missing" };
}

function render({ focus = false, preserveInput = false } = {}) {
  const savedInput = preserveInput ? screen.querySelector("#chat-form input")?.value : "";
  current = route();
  switch (current.page) {
    case "home": screen.innerHTML = home(demo); break;
    case "directory": screen.innerHTML = directory(demo); break;
    case "profiles": screen.innerHTML = (current.edit ? profileEditor : profilesPage)(demo, current.owner); break;
    case "chat": screen.innerHTML = chatPage(demo, current.space, current.moduleId); break;
    case "module": {
      const parameters = {
        ...current,
        content: demo.readContent(current.id, current.draftId, current.version),
        hasBothVersions: demo.hasBothVersions(current.id),
      };
      screen.innerHTML = (current.edit ? moduleEditor : modulePage)(parameters);
      break;
    }
    default: screen.innerHTML = '<section>' + header("页面暂不可用", "#/") +
      '<div class="page-content"><a class="button secondary" href="#/">回到 AI 中枢</a></div></section>';
  }
  document.body.dataset.page = current.page;
  navigation.hidden = !current.nav;
  navigation.innerHTML = current.nav ? nav(current.nav) : "";
  if (savedInput && current.page === "chat") screen.querySelector("#chat-form input").value = savedInput;
  const feed = screen.querySelector("#chat-feed");
  if (feed) feed.scrollTop = feed.scrollHeight;
  if (focus) {
    window.scrollTo(0, 0);
    screen.querySelector("h1")?.focus({ preventScroll: true });
  }
}

function feedback(message, persistent = true) {
  clearTimeout(toastTimer);
  status.textContent = persistent ? message : "浏览器无法保存，本次更改在关闭页面前可用。";
  status.classList.add("visible");
  toastTimer = setTimeout(() => status.classList.remove("visible"), 3500);
}

function showDialog(markup) {
  if (dialog.open) dialog.close();
  dialog.innerHTML = markup;
  dialog.showModal();
}

function changeRoute(path) {
  if (location.hash === path) render({ focus: true });
  else location.hash = path;
}

document.addEventListener("click", (event) => {
  const control = event.target.closest("button[data-action]");
  if (!control) return;
  const { action, id, sample } = control.dataset;
  switch (action) {
    case "choose-actor":
      showDialog(chooser(demo.session().actor));
      break;
    case "close-dialog":
      dialog.close();
      break;
    case "select-actor": {
      const stored = demo.selectActor(id);
      dialog.close();
      if (current.page === "profiles") changeRoute("#/profiles/" + id);
      else render({ focus: true });
      feedback("已切换到演示 " + id.toUpperCase(), stored);
      break;
    }
    case "fill-sample": {
      const field = screen.querySelector("#chat-form input");
      field.value = sample;
      field.focus();
      break;
    }
    case "accept-preference":
    case "discard-preference": {
      const accept = action === "accept-preference";
      const saved = demo.resolvePreference(id, accept);
      render({ preserveInput: true });
      screen.querySelector("#chat-form input")?.focus({ preventScroll: true });
      feedback(accept ? "已加入你的档案" : "已忽略这条候选", saved);
      break;
    }
  }
});

document.addEventListener("submit", (event) => {
  const form = event.target;
  const values = Object.fromEntries(new FormData(form));
  event.preventDefault();
  try {
    switch (form.id) {
      case "chat-form": {
        const result = demo.send({ text: values.message, space: current.space, moduleId: current.moduleId });
        if (!result) {
          feedback("请输入一条消息。");
          return;
        }
        render();
        screen.querySelector("#chat-form input").focus({ preventScroll: true });
        if (!result.persistent) feedback("", false);
        break;
      }
      case "module-form": {
        pending = demo.reviewModule({ ...current, values });
        if (pending) showDialog(reviewBody(pending));
        else feedback("请补全标题、摘要和详情。");
        break;
      }
      case "confirm-module": {
        if (!pending) return;
        const id = pending.id;
        const shared = values.scope === "shared";
        const saved = demo.confirmModule(pending, { shared, remember: values.remember === "on" });
        dialog.close();
        changeRoute(moduleUrl(id, "", false, shared ? "shared" : ""));
        feedback(shared ? "已保存到共同内容" : "已保存到我的演示内容", saved);
        break;
      }
      case "profile-form": {
        const stored = demo.updateProfile(current.owner, values);
        changeRoute("#/profiles/" + current.owner);
        feedback("档案已保存", stored);
        break;
      }
    }
  } catch (error) {
    feedback(error.message || "本次操作未完成。");
  }
});

dialog.addEventListener("close", () => { pending = null; });
window.addEventListener("hashchange", () => {
  if (dialog.open) dialog.close();
  render({ focus: true });
});

render();
