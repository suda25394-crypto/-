import { modules } from "./data.js";
import { actorButton, esc, header, icon, moduleBadge, moduleUrl } from "./ui.js";

export function nav(active) {
  return [
    ["/", "中枢", "orbit"], ["/modules", "功能", "grid"], ["/profiles", "我们", "people"],
  ].map(([path, label, symbol]) => `<a href="#${path}"${active === path ? ' aria-current="page"' : ""}>
    ${icon(symbol)}<span>${label}</span>
  </a>`).join("");
}

export function home(demo) {
  const orbit = demo.orbit();
  const leadId = orbit.includes("date") ? "date" : orbit[0];
  const lead = demo.readContent(leadId);
  return `<section class="home-page">
    <header class="home-header">
      <div class="brand"><span class="brand-mark">${icon("orbit")}</span><span>我们之间</span></div>
      ${actorButton(demo.session().actor)}
    </header>
    <div class="home-intro">
      <h1 tabindex="-1">你们的 AI 中枢</h1>
      <p>把你们想做的事，交给我来整理。</p>
    </div>
    <div class="orbit-stage" aria-label="AI 中枢和最近相关的功能">
      <div class="orbit-ring orbit-ring-outer" aria-hidden="true"></div>
      <div class="orbit-ring orbit-ring-middle" aria-hidden="true"></div>
      <div class="orbit-ring orbit-ring-inner" aria-hidden="true"></div>
      <i class="orbit-dot dot-one" aria-hidden="true"></i><i class="orbit-dot dot-two" aria-hidden="true"></i>
      <a class="ai-core" href="#/chat/personal" aria-label="和 AI 聊聊">
        <span class="core-mark">${icon("sparkles")}</span><strong>AI</strong><span>点我，说需求</span>
      </a>
      ${orbit.map((id, index) => {
        const module = modules[id];
        return `<a href="${moduleUrl(id)}" class="orbit-node node-${index} tone-${module.color}">
          ${icon(module.icon)}<span>${module.name}</span>
        </a>`;
      }).join("")}
    </div>
    <a class="home-card" href="${moduleUrl(leadId)}">
      ${moduleBadge(modules[leadId])}
      <span><small>${modules[leadId].name} · ${lead.scope === "sample" ? "示例" : "已保存"}</small><strong>${esc(lead.title)}</strong></span>
      ${icon("chevron")}
    </a>
    <p class="demo-note">本地演示 · 使用示例账号与模拟 AI</p>
  </section>`;
}

export function directory(demo) {
  return `<section>
    ${header("功能", "#/")}
    <div class="page-content">
      <div class="page-intro"><h2>你们的生活</h2><p>从已有内容出发，随时打开和调整。</p></div>
      <div class="module-grid">
        ${Object.entries(modules).map(([id, module]) => {
          const { title } = demo.readContent(id);
          return `<a class="directory-card tone-${module.color}" href="${moduleUrl(id)}">
            ${moduleBadge(module)}<strong>${module.name}</strong><small>${esc(title)}</small>${icon("chevron")}
          </a>`;
        }).join("")}
      </div>
    </div>
  </section>`;
}

function sourceText(content, draft) {
  if (draft) return "AI 草稿 · 待确认";
  return { sample: "演示示例", personal: "我的演示内容", shared: "共同内容 · 已确认" }[content.scope];
}

function planet() {
  return `<div class="universe-scene" aria-hidden="true">
    <i class="universe-orbit outer"></i><i class="universe-orbit inner"></i>
    <i class="universe-star star-a"></i><i class="universe-star star-b"></i><i class="universe-star star-c"></i>
    <div class="universe-planet"></div>
  </div>`;
}

export function modulePage({ id, draftId, content, version, hasBothVersions }) {
  const module = modules[id];
  if (!content) return `<section>${header(module.name, "#/modules")}
    <div class="page-content empty-state"><h2>这份草稿暂不可用</h2>
      <p>可返回功能查看已保存的内容。</p><a class="button secondary" href="${moduleUrl(id)}">打开${module.name}</a>
    </div></section>`;
  const universe = id === "universe";
  const back = draftId ? "#/chat/" + content.scope : "#/modules";
  const scope = draftId ? content.scope : "personal";
  return `<section class="module-page ${universe ? "universe-page" : ""}">
    ${header(universe ? "我们的小宇宙" : module.name, back)}
    <div class="page-content">
      <div class="module-hero tone-${module.color}">
        ${universe ? planet() : moduleBadge(module)}
        <small>${sourceText(content, draftId)}</small>
        <h2>${esc(content.title)}</h2>
        <p>${esc(content.summary)}</p>
      </div>
      <details class="detail-box">
        <summary>${universe ? "星球故事与场景" : "展开详情"}${icon("down")}</summary>
        <div class="detail-text">${esc(content.details)}</div>
      </details>
      <div class="actions">
        <a class="button secondary" href="#/chat/${scope}?module=${id}">${icon("sparkles")}让 AI 调整</a>
        <a class="button primary" href="${moduleUrl(id, draftId, true, version)}">${icon("edit")}编辑内容</a>
      </div>
      ${!draftId && hasBothVersions ? `<a class="version-link" href="${moduleUrl(id, "", false, content.scope === "shared" ? "personal" : "shared")}">
        ${content.scope === "shared" ? "查看我的版本" : "查看共同版本"}
      </a>` : ""}
    </div>
  </section>`;
}

export function moduleEditor({ id, draftId, version, content }) {
  if (!content) return modulePage({ id, draftId, content });
  return `<section>${header("编辑" + modules[id].name, moduleUrl(id, draftId, false, version))}
    <div class="page-content">
      <p class="context-note">确认前，修改保留在这份表单中。</p>
      <form class="fields" id="module-form">
        <div class="field"><label for="module-title">标题</label><input id="module-title" name="title" maxlength="65" required value="${esc(content.title)}"></div>
        <div class="field"><label for="module-summary">摘要</label><textarea id="module-summary" name="summary" rows="3" maxlength="280" required>${esc(content.summary)}</textarea></div>
        <div class="field"><label for="module-details">详情</label><textarea id="module-details" name="details" rows="6" maxlength="1300" required>${esc(content.details)}</textarea></div>
        <button class="button primary full" type="submit">${icon("sparkles")}查看 AI 确认</button>
      </form>
    </div>
  </section>`;
}

export function reviewBody(review) {
  const fields = { title: "标题", summary: "摘要", details: "详情" };
  const edits = review.changed.map((key) => fields[key]).join("、");
  return `<form id="confirm-module">
    <header class="dialog-header"><div><small>本地模拟分析</small><h2 id="review-title">AI 修改确认</h2></div>
      <button class="icon-button" type="button" data-action="close-dialog" aria-label="关闭确认">${icon("close")}</button></header>
    <p class="review-summary">${edits ? "你调整了" + edits + "。请确认预览和保存范围。" : "内容与原先一致。你仍可以确认保存。"} </p>
    <div class="review-preview"><strong>${esc(review.candidate.title)}</strong><p>${esc(review.candidate.summary)}</p>
      <details><summary>查看完整详情</summary><div class="detail-text">${esc(review.candidate.details)}</div></details>
    </div>
    <fieldset>
      <legend>保存范围</legend>
      <label class="choice"><input type="radio" name="scope" value="personal" ${review.scope !== "shared" ? "checked" : ""}>我的演示内容</label>
      <label class="choice"><input type="radio" name="scope" value="shared" ${review.scope === "shared" ? "checked" : ""}>共同内容，两位演示用户可见</label>
    </fieldset>
    <label class="choice remember"><input type="checkbox" name="remember">将这次修改加入我的演示记忆</label>
    <div class="actions">
      <button type="button" class="button secondary" data-action="close-dialog" autofocus>继续编辑</button>
      <button class="button primary" type="submit">确认保存</button>
    </div>
  </form>`;
}
