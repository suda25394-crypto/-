import { defaultOrbit, modules, profileFields, profiles } from "./data.js";
import { analyze } from "./director.js";

const STORAGE_KEY = "between-us.frontend-demo.v1";
const people = ["a", "b"];
const limit = 40;

function starter() {
  return {
    version: 1,
    actor: "a",
    profiles: structuredClone(profiles),
    chats: { a: [], b: [], shared: [] },
    content: { a: {}, b: {}, shared: {} },
    memory: { a: [], b: [] },
    orbit: { a: [...defaultOrbit], b: [...defaultOrbit] },
  };
}

function restore() {
  try {
    const saved = JSON.parse(localStorage.getItem(STORAGE_KEY));
    if (saved?.version === 1
      && people.includes(saved.actor)
      && [...people, "shared"].every((key) => Array.isArray(saved.chats?.[key]) && saved.content?.[key])
      && people.every((key) => Array.isArray(saved.profiles?.[key]?.confirmed)
        && Array.isArray(saved.memory?.[key]) && Array.isArray(saved.orbit?.[key]))) {
      return saved;
    }
  } catch {
    // A fresh demo remains usable if the browser blocks storage or stored data was invalid.
  }
  return starter();
}

let state = restore();

function write(change) {
  const next = structuredClone(state);
  change(next);
  state = next;
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
    return true;
  } catch {
    return false;
  }
}

function sessionSpace(space) {
  return space === "shared" ? "shared" : state.actor;
}

function newKey() {
  const entropy = crypto.getRandomValues(new Uint32Array(2)).join("-");
  return Date.now().toString(36) + "-" + entropy;
}

function clean(value, max) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function findCard(id, draftId) {
  return [...state.chats[state.actor], ...state.chats.shared]
    .flatMap((message) => message.cards ?? [])
    .find((card) => card.id === draftId && card.moduleId === id);
}

function readContent(id, draftId = "", version = "") {
  if (!Object.hasOwn(modules, id)) return null;
  if (draftId) return findCard(id, draftId) ?? null;
  const local = state.content[state.actor][id];
  const shared = state.content.shared[id];
  if (version === "shared" && shared) return { ...shared, scope: "shared" };
  if (local) return { ...local, scope: "personal" };
  if (shared) return { ...shared, scope: "shared" };
  const { title, summary, details } = modules[id];
  return { title, summary, details, scope: "sample" };
}

function selectActor(actor) {
  if (!people.includes(actor)) return false;
  return write((next) => { next.actor = actor; });
}

function send({ text, space, moduleId }) {
  if (!["personal", "shared"].includes(space)) throw new Error("无效的对话入口");
  const input = clean(text, 350);
  if (!input) return null;
  const scope = sessionSpace(space);
  const replies = space === "personal" || /@AI\b/iu.test(input);
  const target = moduleId && Object.hasOwn(modules, moduleId) ? moduleId : undefined;
  const result = replies ? analyze({
    input,
    space,
    moduleId: target,
    people: Object.values(state.profiles),
    personalMemory: space === "personal" ? state.memory[state.actor].map((item) => item.summary) : [],
  }) : null;
  const persistent = write((next) => {
    const messages = next.chats[scope];
    messages.push({ id: newKey(), author: next.actor, text: input });
    if (result) {
      const cards = result.cards.map((card) => ({
        ...card, id: newKey(), scope: space,
      }));
      messages.push({
        id: newKey(), author: "ai", text: result.text, cards,
        preference: result.preference ? { value: result.preference, status: "pending" } : null,
      });
      if (cards.length) {
        const renewed = [...new Set([...cards.map((card) => card.moduleId), ...defaultOrbit])].slice(0, 4);
        for (const actor of space === "shared" ? people : [next.actor]) next.orbit[actor] = renewed;
      }
    }
    next.chats[scope] = messages.slice(-limit);
  });
  return { persistent };
}

function reviewModule({ id, draftId, version, values }) {
  const before = readContent(id, draftId, version);
  if (!before) return null;
  const candidate = {
    title: clean(values.title, 65),
    summary: clean(values.summary, 280),
    details: clean(values.details, 1300),
  };
  if (Object.values(candidate).some((value) => !value)) return null;
  return {
    id, draftId, version, actor: state.actor, candidate, scope: before.scope,
    changed: ["title", "summary", "details"].filter((key) => candidate[key] !== before[key]),
  };
}

function confirmModule(review, { shared, remember }) {
  if (review.actor !== state.actor || !readContent(review.id, review.draftId, review.version)) {
    throw new Error("这份修改已失效，请重新打开详情。");
  }
  return write((next) => {
    const actor = next.actor;
    const scope = shared ? "shared" : actor;
    next.content[scope][review.id] = { ...review.candidate };
    if (remember) {
      const item = {
        id: newKey(),
        title: modules[review.id].name + " · " + review.candidate.title,
        summary: review.candidate.summary,
      };
      next.memory[actor] = [...next.memory[actor], item].slice(-limit);
    }
  });
}

function updateProfile(owner, values) {
  if (owner !== state.actor) throw new Error("只有本人可以编辑这份档案。");
  return write((next) => {
    for (const [key, , max] of profileFields) next.profiles[owner][key] = clean(values[key], max);
  });
}

function resolvePreference(messageId, accept) {
  const message = state.chats[state.actor].find((item) => item.id === messageId);
  if (message?.preference?.status !== "pending") return false;
  return write((next) => {
    const proposal = next.chats[next.actor].find((item) => item.id === messageId).preference;
    proposal.status = accept ? "accepted" : "dismissed";
    if (accept) {
      const profile = next.profiles[next.actor];
      profile.confirmed = [...new Set([...profile.confirmed, proposal.value])].slice(-limit);
    }
  });
}

export const demo = {
  session: () => ({ actor: state.actor, mode: "local-demo" }),
  selectActor,
  profile: (owner) => people.includes(owner) ? structuredClone(state.profiles[owner]) : null,
  updateProfile,
  chat: (space) => structuredClone(state.chats[sessionSpace(space)]),
  send,
  resolvePreference,
  memory: () => structuredClone(state.memory[state.actor]),
  orbit: () => [...new Set([
    ...state.orbit[state.actor].filter((id) => Object.hasOwn(modules, id)), ...defaultOrbit,
  ])].slice(0, 4),
  readContent,
  hasBothVersions: (id) => Boolean(state.content[state.actor][id] && state.content.shared[id]),
  reviewModule,
  confirmModule,
};
