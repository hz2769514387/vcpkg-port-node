// 场景六里 node 那一侧的脚本：嵌入运行时里，node 的并发模型还完整吗？
//
// 消费方最常见的一问："我把 node 嵌进我的程序了，worker_threads 还能用吗？"
// 能 —— worker 是 **node 运行时内部**的能力，与"谁调用的 node::Start"无关；
// 反过来，主线程怎么被宿主使用也影响不到 worker。
//
// 本脚本让 3 个 worker 真干活：每个用 node 的 zlib 压一段自己的数据再解回来
// 逐字节核对（顺带证明 worker 里 vcpkg 提供的库同样是好的），主线程收齐
// 3 个结果后打印汇总。任何一条不对就以非零退出 —— 嵌入运行时如实透传。
const { Worker, isMainThread, parentPort, workerData } = require('node:worker_threads');

const kWorkers = 3;

if (!isMainThread) {
  // ---- worker 侧：真做点活 -------------------------------------------------
  const zlib = require('node:zlib');
  const payload = `worker-${workerData.id}-${workerData.seed}`;
  const back = zlib.inflateSync(zlib.deflateSync(payload)).toString('utf8');
  parentPort.postMessage(
    back === payload ? `w${workerData.id}:zlib-ok` : `w${workerData.id}:FAIL-roundtrip`
  );
} else {
  // ---- 主线程侧：起 worker、收结果、汇总 ------------------------------------
  const results = [];
  let done = 0;
  let failed = false;

  for (let i = 0; i < kWorkers; i++) {
    const worker = new Worker(__filename, {
      workerData: { id: i, seed: `seed-${i}` },
    });
    worker.on('message', (m) => {
      results.push(m);
      if (++done < kWorkers) return;
      results.sort();
      if (failed || results.some((r) => !r.endsWith(':zlib-ok'))) {
        console.error(`WORKERS-FAIL ${results.join(' ')}`);
        process.exit(1);
      }
      console.log(`WORKERS-OK ${results.join(' ')}`);
    });
    worker.on('error', (e) => {
      failed = true;
      console.error(`WORKERS-FAIL worker error: ${e.message}`);
      process.exit(1);
    });
  }
}
