import { modules, profileFields } from "./data.js";
import { actorButton, esc, header, icon, moduleBadge, moduleUrl } from "./ui.js";

function conversationMessage(message, actor) {
  const assistant = message.author === "ai";
  const speaker = assistant ? "小智 · 模拟" : message.author === actor ? "我" : "演示 " + message.author.toUpperCase();
  return `<article class="message ${assistant ? "assistant" : message.author === actor ? "mine" : "partner"}">
    <small>${esc(speaker)}</small><p>${esc(message.text)}</p>
    ${message.cards?.length ? `<div class="suggestions" aria-label="关联功能草稿">
      ${message.cards.map((card) => `<a class="suggestion" href="${moduleUrl(card.moduleId, card.id)}">
        ${moduleBadge(modules[card.moduleId])}
        <span><small>${modules[card.moduleId].name} · 待确认</small><strong>${esc(card.title)}</strong></span>${icon("chevron")}
      </a>`).join("")}
    </div>` : ""}
    ${message.preference ? preferenceCard(message) : ""}
  </article>`;
}

function preferenceCard(message) {
  const { preference } = message;
  if (preference.status === "accepted") return '<p class="preference-status">已确认加入我的档案</p>';
  if (preference.status === "dismissed") return '<p class="preference-status">已忽略这条候选</p>';
  return `<div class="preference-card"><strong>加入你的档案？</strong>
    <p>${esc(preference.value)}</p><small>确认后，另一位演示用户也能在你的档案中看到。</small>
    <div class="actions">
      <button class="button secondary" type="button" data-action="discard-preference" data-id="${esc(message.id)}">忽略</button>
      <button class="button primary" type="button" data-action="accept-preference" data-id="${esc(message.id)}">加入我的档案</button>
    </div></div>`;
}

export function chatPage(demo, space, moduleId) {
  const shared = space === "shared";
  const actor = demo.session().actor;
  const messages = demo.chat(space);
  const sample = shared ? "@AI 周末有空，帮我们安排一下。" : "周末想和女朋友出去玩，预算 200 元。";
  const back = moduleId ? moduleUrl(moduleId) : "#/";
  return `<section class="chat-page">
    <header class="page-header">
      <a class="icon-button" href="${back}" aria-label="返回">${icon("back")}</a>
      <div><h1 tabindex="-1">${shared ? "我们和 AI" : "小智"}</h1><small>本地模拟</small></div>
      ${actorButton(actor)}
    </header>
    <nav class="segments chat-segments" aria-label="切换对话">
      <a href="#/chat/personal"${!shared ? ' aria-current="page"' : ""}>个人 AI</a>
      <a href="#/chat/shared"${shared ? ' aria-current="page"' : ""}>共同空间</a>
    </nav>
    <div class="chat-feed" id="chat-feed" role="log" aria-label="对话消息">
      ${messages.length ? messages.map((item) => conversationMessage(item, actor)).join("") :
        `<div class="chat-welcome">
          <span class="welcome-icon">${icon("sparkles")}</span>
          <h2>${shared ? "和伴侣一起聊" : "今天想做什么？"}</h2>
          <p>${shared ? "两位演示用户都能看到这里的消息。输入 @AI 获取模拟回复。" : "说说你的需求，我会整理成可以点开和修改的功能卡片。"}</p>
          <button class="sample-button" type="button" data-action="fill-sample" data-sample="${esc(sample)}">${esc(sample)} ${icon("arrow")}</button>
        </div>`}
    </div>
    <form id="chat-form" class="composer">
      ${moduleId ? `<p class="context-note">正在调整 · ${modules[moduleId].name}</p>` : ""}
      <div class="composer-inner">
        <input name="message" aria-label="输入消息" placeholder="${shared ? "输入消息或 @AI…" : "说说你的需求…"}" maxlength="350" required autocomplete="off">
        <button class="send-button" type="submit" aria-label="发送消息">${icon("send")}</button>
      </div>
    </form>
  </section>`;
}

function emptyRadar() {
  return `<figure class="radar-card">
    <div class="radar" aria-hidden="true">
      <svg viewBox="0 0 140 134" fill="none" stroke="currentColor">
        <polygon points="70,8 125,48 104,113 36,113 15,48"/>
        <polygon points="70,23 111,53 95,102 45,102 29,53"/>
        <polygon points="70,38 97,58 87,91 53,91 43,58"/>
        <polygon points="70,53 84,63 79,79 61,79 56,63"/>
        <path d="M70 66 70 8m0 58 55-18m-55 18 34 47m-34-47-34 47m34-47L15 48"/>
      </svg>
    </div>
    <figcaption><strong>五维人格图</strong><span>尚未测量</span>
      <small>外向 · 亲和 · 条理 · 情绪敏感 · 想象开放</small>
    </figcaption>
  </figure>`;
}

export function profilesPage(demo, owner) {
  const actor = demo.session().actor;
  const person = demo.profile(owner);
  const own = actor === owner;
  const notes = own ? demo.memory() : [];
  return `<section>
    <header class="home-header sub-header">
      <h1 tabindex="-1">我们的小档案</h1>${actorButton(actor)}
    </header>
    <div class="page-content profile-content">
      <nav class="segments" aria-label="两人档案">
        ${["a", "b"].map((id) => `<a href="#/profiles/${id}"${id === owner ? ' aria-current="page"' : ""}>
          演示 ${id.toUpperCase()}${id === actor ? "（我）" : ""}
        </a>`).join("")}
      </nav>
      <article class="profile-card">
        <div class="profile-title"><span class="avatar avatar-${owner}">${owner.toUpperCase()}</span>
          <div><h2>${esc(person.name)}</h2><small>双方可见 · 演示档案</small></div>
        </div>
        <p class="portrait">${esc(person.portrait || "文字画像尚未填写。")}</p>
        ${emptyRadar()}
      </article>
      <details class="detail-box profile-details">
        <summary>生活与相处偏好${icon("down")}</summary>
        <dl>${profileFields.filter(([key]) => key !== "portrait").map(([key, label]) =>
          `<dt>${label}</dt><dd>${esc(person[key] || "尚未填写")}</dd>`).join("")}</dl>
        ${person.confirmed.length ? `<h3>已确认加入的偏好</h3><ul>${person.confirmed.map((pref) => `<li>${esc(pref)}</li>`).join("")}</ul>` : ""}
      </details>
      ${own ? `<div class="actions">
        <a class="button primary" href="#/profiles/${owner}/edit">${icon("edit")}编辑我的档案</a>
      </div>
      <details class="detail-box">
        <summary>我的演示记忆 · ${notes.length} 条${icon("down")}</summary>
        ${notes.length ? `<ul class="memory-list">${notes.map((entry) =>
          `<li><strong>${esc(entry.title)}</strong><p>${esc(entry.summary)}</p></li>`).join("")}</ul>` :
          "<p>在模块确认时选择加入记忆，记录会出现在这里。</p>"}
      </details>` : '<p class="context-note">伴侣本人可以修改这份档案。</p>'}
      <a class="button secondary full" href="#/chat/shared">${icon("chat")}打开共同空间</a>
    </div>
  </section>`;
}

export function profileEditor(demo, owner) {
  if (demo.session().actor !== owner) return profilesPage(demo, owner);
  const profile = demo.profile(owner);
  return `<section>${header("编辑我的档案", "#/profiles/" + owner)}
    <div class="page-content">
      <p class="context-note">保存后，这些自述会显示在本机的双人演示档案中。</p>
      <form id="profile-form" class="fields">
        ${profileFields.map(([key, label, max]) =>
          `<div class="field"><label for="profile-${key}">${label}</label><textarea id="profile-${key}" name="${key}" rows="3" maxlength="${max}">${esc(profile[key])}</textarea></div>`).join("")}
        <button type="submit" class="button primary full">保存档案</button>
      </form>
    </div>
  </section>`;
}

export function chooser(actor) {
  return `<div class="dialog-header"><div><small>本地演示</small><h2 id="review-title">切换演示账号</h2></div>
    <button type="button" class="icon-button" data-action="close-dialog" aria-label="关闭">${icon("close")}</button></div>
    <p class="review-summary">切换后可以体验另一位成员看到的内容。</p>
    <div class="actor-list">${["a", "b"].map((id) => `<button type="button" data-action="select-actor" data-id="${id}" ${id === actor ? "disabled" : ""}>
      <span class="avatar avatar-${id}">${id.toUpperCase()}</span>
      <strong>演示 ${id.toUpperCase()}</strong><small>${id === actor ? "当前账号" : "切换"}</small>
    </button>`).join("")}</div>`;
}
