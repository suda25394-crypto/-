import { modules } from "../frontend/src/data.js";

export const directions = {
  a: { name: "立体生命中枢", note: "折射玻璃 · 连接式中枢" },
  b: { name: "情侣生活杂志", note: "纸张拼贴 · 编辑叙事" },
  c: { name: "2.5D 浪漫空间", note: "等距场景 · 空间触点" },
};
export const pages = { home: "AI 首页", modules: "功能目录", universe: "小宇宙" };

const shapes = ["sun", "flare", "ripple", "kite", "scope", "plate", "date", "dialogue", "photo", "dice", "gift", "path"];
export const features = Object.fromEntries(Object.entries(modules).map(([id, item], index) =>
  [id, { ...item, shape: shapes[index] }]));
export const zones = [
  { title: "计划与日常", ids: ["date", "calendar", "food", "journey"] },
  { title: "心意与互动", ids: ["surprise", "wish", "game", "gift"] },
  { title: "故事与关系", ids: ["memory", "talk", "photo", "universe"] },
];
export const starting = {
  note: "把散步、见面时间和一个共同心愿串起来。",
  ids: ["date", "calendar", "wish"],
};
export const world = {
  name: "湖畔观测站",
  chapter: "湖边的第一盏灯",
  summary: "阿澄和小屿沿湖走到观测站，把第一次共同看日落的记忆留给今晚。",
  people: [["阿澄", "喜欢沿水边慢慢走"], ["小屿", "习惯把故事写进小纸条"]],
  places: [
    ["观测站", "沿着台阶上到观测站，可以透过玻璃穹顶看天色慢慢变暗。"],
    ["湖边步道", "阿澄沿水边等小屿，水上还有今天最后一点光。"],
    ["信笺角", "小屿写下第一次一起看日落的细节，把它留给两个人。"],
  ],
};

export function director(text, context) {
  if (context === "universe") {
    const lights = /灯|星|夜|亮/u.test(text);
    return { ids: ["universe", "memory", "wish"], note: lights
      ? "将观测站的窗灯加入场景草案，再把今天的回忆附到下一章。"
      : "从信笺角展开下一章，关联共同记忆和心愿。" };
  }
  if (/惊喜|生日|礼物|纪念/u.test(text)) {
    return { ids: ["surprise", "gift", "calendar"], note: "先写下惊喜与礼物方向，再挑一个双方有空的时段。" };
  }
  if (/回忆|照片|记忆|相册/u.test(text)) {
    return { ids: ["memory", "photo", "universe"], note: "先整理共同回忆和相册，再把适合的片段留给故事。" };
  }
  return starting;
}
