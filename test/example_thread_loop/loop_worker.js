// 场景四里 node 那一侧的脚本 —— 它跑在**宿主的 worker 线程**中（node::Start
// 就在那个线程里被调用），主线程同时还在跑宿主自己的循环。
//
// 这个脚本只做一件事：轮询宿主投递消息的目录，来一条回一条；看到收场信号
// 且没有待处理消息后主动退出。退出码 0 会经 node::Start 的返回值传给宿主，
// 宿主再原样变成自己进程的退出码（场景③的那条链，这里原样走一遍）。
//
// 用法（由宿主拼好 argv，人也可以直接跑）：
//   node loop_worker.js <邮箱目录>

const fs = require('node:fs');
const path = require('node:path');

const mailbox = process.argv[2];
if (!mailbox) {
  console.error('用法: node loop_worker.js <mailbox-dir>');
  process.exit(2);
}

const kPollMs = 25;

// 文件名自带序号；seen 只防极端情况下的重复处理（正常流程读完即删）。
const seen = new Set();
let processed = 0;

function listPrefix(prefix) {
  try {
    return fs.readdirSync(mailbox).filter((f) => f.startsWith(prefix));
  } catch {
    return [];  // 目录还没建好：下一轮再看
  }
}

// 与宿主同一套原子写：先临时名、再 rename。读者永远不会读到半条消息。
function writeReply(n, text) {
  const seq = String(n).padStart(6, '0');
  const final = path.join(mailbox, `n2h-${seq}.rpy`);
  const tmp = `${final}.tmp`;
  fs.writeFileSync(tmp, text);
  fs.renameSync(tmp, final);
}

console.log(`JS-START mailbox=${mailbox}`);

const timer = setInterval(() => {
  for (const name of listPrefix('h2n-')) {
    if (!name.endsWith('.msg') || seen.has(name)) continue;  // .tmp 半成品跳过
    seen.add(name);
    // 回复文件名用**消息序号**（从 h2n-<seq>.msg 里取），不用自己的处理计数：
    // 这样回复名永远落在 n2h-000001..N 这个集合里 —— 万一上轮有陈旧消息文件
    // 没清掉，它的回复也只会同名碰撞（rename 覆盖），不会冒出集合外的新名字，
    // 宿主按名去重后计数依然确定。
    const m = /^h2n-(\d+)\.msg$/.exec(name);
    if (!m) continue;
    const seq = m[1];
    const text = fs.readFileSync(path.join(mailbox, name), 'utf8').trim();
    fs.rmSync(path.join(mailbox, name), { force: true });
    processed += 1;
    // 这行会打进 ctest 日志，和宿主的 HOST-TICK 交错出现 ——
    // 肉眼就能看出"两个循环同时在跑"。
    console.log(`JS-GOT ${text}`);
    writeReply(seq, `NODE-REPLY ${seq}\n`);
  }
  // 收场条件：宿主喊了 stop，且没有待处理的 h2n 消息（.tmp 也算没处理完）。
  if (fs.existsSync(path.join(mailbox, 'stop')) &&
      listPrefix('h2n-').length === 0) {
    clearInterval(timer);
    console.log(`JS-DONE processed=${processed}`);
    // ★ 嵌入场景的关键一课：**不要**用 process.exit(N) 收场。
    //   process.exit() 走的是 libc exit()，带走的是**整个宿主进程** ——
    //   node 只是宿主 worker 线程里的一段代码，宿主线程后面的收场逻辑
    //   （join、断言、把自己的退出码传给它的调用方）全都来不及执行。
    //   2026-10-14 本示例第一版正是这么写的，现象是宿主在 tick 30 左右
    //   被"腰切"，THREAD-LOOP-OK 永远打不出来。
    //   正确做法：process.exitCode = N（默认 0，这行是显式给消费方看的），
    //   让脚本自然结束 ⇒ node 的事件循环耗尽 ⇒ node::Start **返回** N
    //   ⇒ 宿主线程拿到返回值，该收的尾一分不少。
    //   （场景③ example_host_exit 里 process.exit(N) 是对的 —— 那边 node
    //     就是整个进程；区别只在"谁调用 node::Start"。）
    process.exitCode = 0;
  }
}, kPollMs);
