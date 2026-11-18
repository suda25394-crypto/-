enum ModuleId {
  date,
  surprise,
  memory,
  wish,
  universe,
  food,
  calendar,
  talk,
  album,
  game,
  gift,
  travel,
}

class CoupleModule {
  const CoupleModule(this.id, this.name, this.summary, this.steps);

  final ModuleId id;
  final String name;
  final String summary;
  final List<String> steps;
}

const catalog = <ModuleId, CoupleModule>{
  ModuleId.date: CoupleModule(ModuleId.date, '约会', '留出一个慢慢过的下午。', [
    '在河边散步',
    '挑一家两个人都想试的小店',
    '给返程留一点余地',
  ]),
  ModuleId.surprise: CoupleModule(ModuleId.surprise, '惊喜', '为对方留一点意外的开心。', [
    '想起一件最近让你开心的小事',
    '把它写进一张卡片',
    '自己选什么时候交给对方',
  ]),
  ModuleId.memory: CoupleModule(ModuleId.memory, '共同记忆', '记下第一次一起看日落。', [
    '选一段你们都愿意分享的经历',
    '各写下一个记得的细节',
    '给这段回忆起一个名字',
  ]),
  ModuleId.wish: CoupleModule(ModuleId.wish, '心愿', '一起看一场海边日出。', [
    '挑两个都方便的周末',
    '记下想去的海边',
    '出发前核对天气和交通',
  ]),
  ModuleId.universe: CoupleModule(ModuleId.universe, '小宇宙', '给你们的共同故事留一个地方。', [
    '点亮两个人的观察站',
  ]),
  ModuleId.food: CoupleModule(ModuleId.food, '美食', '把今晚想吃的东西放在一起。', [
    '先对一对口味和忌口',
    '看看想一起做饭还是出门',
    '留一点时间好好吃饭',
  ]),
  ModuleId.calendar: CoupleModule(ModuleId.calendar, '共同日程', '给周末留一段相处时间。', [
    '各自确认方便的时间',
    '商量见面地点',
    '把计划留给双方核对',
  ]),
  ModuleId.talk: CoupleModule(ModuleId.talk, '关系沟通', '找不赶时间的时刻谈感受。', [
    '从一件具体的事说起',
    '轮流听完对方的感受',
    '商量一个愿意尝试的小改变',
  ]),
  ModuleId.album: CoupleModule(ModuleId.album, '情侣相册', '给一起拍的照片写一句话。', [
    '选双方都愿意分享的照片',
    '回想那天的天气和声音',
    '为这一组照片起名',
  ]),
  ModuleId.game: CoupleModule(ModuleId.game, '互动游戏', '来一局十分钟的默契问答。', [
    '各自写下想一起做的事',
    '同时揭晓答案',
    '把一件共同想做的事留作心愿',
  ]),
  ModuleId.gift: CoupleModule(ModuleId.gift, '礼物灵感', '从对方提过的小事寻找灵感。', [
    '回想对方主动说过的喜好',
    '决定预算',
    '再挑选想送的心意',
  ]),
  ModuleId.travel: CoupleModule(ModuleId.travel, '旅行', '挑一个周末能轻松到达的地方。', [
    '约定路程与预算',
    '列出两个目的地备选',
    '敲定日期后自己核对交通',
  ]),
};

const initialSuggestions = [ModuleId.date, ModuleId.memory, ModuleId.wish];

class DemoProfile {
  const DemoProfile(this.name, this.favorite, this.habit, this.preference);

  final String name;
  final String favorite;
  final String habit;
  final String preference;
}

const demoProfiles = [
  DemoProfile('演示 A', '散步、咖啡和电影。', '周末下午通常有空。', '烦心时希望先被听完。'),
  DemoProfile('演示 B', '绿地、手作和偶尔看展。', '喜欢在活动之间留点空白。', '愿意轮流发起下一次约会。'),
];
