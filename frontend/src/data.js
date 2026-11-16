export const modules = {
  date: {
    name: "约会", color: "peach", icon: "sun", title: "留一个慢慢过的下午",
    summary: "沿着河边散步，找一家安静的小店坐坐。",
    details: "下午见面，先沿河散步。\n挑选两个人都愿意尝试的小店。\n给返程留出弹性。",
  },
  surprise: {
    name: "惊喜", color: "blue", icon: "sparkles", title: "夹在书里的小纸条",
    summary: "写下对方最近让你开心的一件小事。",
    details: "选一件具体的小事。\n写进一张手写卡。\n自己决定何时送出。",
  },
  memory: {
    name: "共同记忆", color: "mint", icon: "clock", title: "第一次一起看日落",
    summary: "把你们记得的小细节留在同一段故事里。",
    details: "那天散步时，天边慢慢变成了橘色。\n给这段回忆留一句你们都愿意分享的话。",
  },
  wish: {
    name: "心愿", color: "sand", icon: "diamond", title: "一起看一场海边日出",
    summary: "从挑两个都方便的日子开始。",
    details: "各自挑一个有空的周末。\n记下想去的海边。\n出发前核实天气与交通。",
  },
  universe: {
    name: "小宇宙", color: "lilac", icon: "planet", title: "两个人的微光星球",
    summary: "初次相遇化作草地上的第一盏灯。",
    details: "第一章 · 相遇的草地\n沿着微光小径走，在草地上留下一句两个人的故事。\n下一章：等待你们写下新的场景。",
  },
  food: {
    name: "美食", color: "peach", icon: "food", title: "今晚一起做番茄意面",
    summary: "一顿容易准备的晚餐，给聊天腾出点时间。",
    details: "先对一下口味和忌口。\n准备番茄、意面和当季蔬菜。\n留十分钟一起收拾厨房。",
  },
  calendar: {
    name: "共同日程", color: "mint", icon: "calendar", title: "周末见面",
    summary: "周六下午预留一段相处时间，具体时间待商量。",
    details: "分别确认周六下午是否有空。\n约好见面时间及地点。\n这里的安排仅保存在浏览器演示中。",
  },
  talk: {
    name: "关系沟通", color: "lilac", icon: "chat", title: "先把感受说清楚",
    summary: "用一句具体的感受，开启一次不赶时间的对话。",
    details: "从「那件事发生时，我感到……」开始。\n请对方复述自己理解到的意思。\n一起商量一个愿意尝试的小改变。",
  },
  photo: {
    name: "情侣相册", color: "blue", icon: "image", title: "散步照片的故事",
    summary: "给散步时拍的那组照片起个名字。",
    details: "选一张你们都愿意分享的照片。\n写上这个地点让你记住的声音或天气。\n本版可以编辑相册说明。",
  },
  game: {
    name: "互动游戏", color: "sand", icon: "game", title: "十分钟默契问答",
    summary: "各写一件想一起做的事，再同时揭晓答案。",
    details: "出一题：下个空闲下午最想一起做什么？\n各自写下答案，再一起揭晓。\n挑一个答案变成心愿。",
  },
  gift: {
    name: "礼物灵感", color: "peach", icon: "gift", title: "一份带着回忆的小礼物",
    summary: "从手写卡和一张共同照片开始。",
    details: "回想一次对方主动提起的喜好。\n先设定花费范围。\n在买之前比较可选的做法。",
  },
  journey: {
    name: "旅行", color: "blue", icon: "compass", title: "周末附近走一走",
    summary: "列出两个轻松可达的方向，再决定去哪里。",
    details: "约定最多能接受的路程和花费。\n准备两个方向：近郊公园或安静小镇。\n确定日期后自行核实路线和价格。",
  },
};

export const defaultOrbit = ["memory", "date", "surprise", "wish"];

export const profiles = {
  a: {
    name: "演示 A",
    likes: "散步、咖啡、看电影",
    habits: "通常周末下午有空，出门前想先约个大概时间。",
    relationship: "遇到烦心事时，希望有人先听我说完。",
    portrait: "喜欢慢一点的相处节奏，愿意一起尝试新的路线。",
    confirmed: [],
  },
  b: {
    name: "演示 B",
    likes: "绿地、手作、偶尔去看展",
    habits: "喜欢活动之间留一点空白，临时变动可以提前说一声。",
    relationship: "一起决定去哪里，也愿意轮流发起下一次约会。",
    portrait: "喜欢自然的惊喜。比起安排得很满，更在意相处的质量。",
    confirmed: [],
  },
};

export const profileFields = [
  ["likes", "生活偏好", 160],
  ["habits", "习惯", 180],
  ["relationship", "相处偏好", 180],
  ["portrait", "文字画像", 200],
];
