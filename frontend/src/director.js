import { modules } from "./data.js";

const routes = [
  { pattern: /旅行|出游|出发|郊游|短途|海边/, ids: ["journey", "date", "calendar", "wish"], reason: "先确定出发方向，再把时间与待办拆开。" },
  { pattern: /约会|周末|出去|见面|散步|出门/, ids: ["date", "calendar", "journey", "wish"], reason: "先给约会留出时间，再选路线和想做的事。" },
  { pattern: /午饭|晚饭|吃|餐厅|下厨|美食/, ids: ["food", "date", "calendar"], reason: "把餐食选项、见面安排和时间放在一起。" },
  { pattern: /惊喜|生日|礼物|纪念日/, ids: ["surprise", "gift", "calendar"], reason: "先准备心意和时机，把发送或购买留给你决定。" },
  { pattern: /沟通|吵架|误会|委屈|和好/, ids: ["talk", "memory", "wish"], reason: "先整理感受，再决定要不要保留一段共同记录。" },
  { pattern: /宇宙|星球|世界|故事/, ids: ["universe", "memory", "wish"], reason: "从共同经历里选一个片段，为小宇宙写下一章。" },
  { pattern: /记忆|回忆|照片|相册|记录/, ids: ["memory", "photo", "universe"], reason: "把想留下的片段整理成一份可回看的故事。" },
  { pattern: /游戏|一起玩|无聊|互动/, ids: ["game", "wish", "memory"], reason: "先试一项轻松的互动，再看看有没有新的共同心愿。" },
  { pattern: /心愿|清单|想实现|目标/, ids: ["wish", "calendar", "date"], reason: "先选一件近期能完成的心愿，再留出时间。" },
  { pattern: /日程|提醒|安排|时间|计划/, ids: ["calendar", "date", "wish"], reason: "先确定时间和优先事项，细节可以稍后补齐。" },
];

function proposalFrom(input, space) {
  const preference = /^(?:其实[，,]?\s*)?我(?:更|很|比较|不|最)?(?:喜欢|希望|偏好|习惯|想避开|想要)[^？?\n]{2,100}[。！!]?$/u;
  return space === "personal" && preference.test(input) ? input : "";
}

export function analyze({ input, space, people, personalMemory, moduleId }) {
  const selected = routes.find((item) => item.pattern.test(input));
  const ids = [...new Set([...(moduleId ? [moduleId] : []), ...(selected?.ids ?? [])])].slice(0, 4);
  const preference = proposalFrom(input, space);
  if (!ids.length) {
    const text = preference
      ? "我整理出一条偏好候选。你可以自己决定要不要把它加入档案。"
      : space === "shared"
        ? "我看到了这条共同空间消息。提到 @AI，并说说想一起做什么，我会整理对应的示例方案。"
        : "可以告诉我这次想做什么，比如安排周末见面、准备礼物，或者整理一份共同回忆。";
    return { text, cards: [], preference };
  }

  const budget = input.match(/(?:预算|不超过|控制在|最多)\s*(?:约|在|为)?\s*(\d{1,5})\s*(?:元|块)?/u)?.[1];
  const publicContext = people.flatMap((person) => [person.likes, ...person.confirmed]);
  const quiet = /不喜欢人多|怕人多|讨厌人多|避开(?:人多|拥挤)|喜欢安静|偏好安静|想安静|清静|错峰/u.test([input, ...publicContext, ...personalMemory].join(" "));
  const relevant = selected?.reason ?? "我把你的需求整理成这项功能的草稿。";
  const cards = ids.map((id) => {
    const sample = modules[id];
    const logistical = ["date", "journey", "gift", "food"].includes(id);
    const summary = id === "date" && quiet
      ? "先选错峰的散步路线，再找一处安静的小店坐坐。"
      : sample.summary;
    const title = id === "date" && quiet ? "去一个清静的地方约会" : sample.title;
    const context = logistical && budget ? "\n预算上限：" + budget + " 元，实际花费待确认。" : "";
    return { moduleId: id, title, summary, details: sample.details + context };
  });
  const preferenceHint = quiet && ids.includes("date") ? "我也把人少、安静作为这次约会的条件。" : "";
  return { text: relevant + preferenceHint, cards, preference };
}
