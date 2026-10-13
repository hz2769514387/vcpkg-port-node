// 场景③-c：脚本显式 process.exit(7) —— 宿主必须原样拿到 7。
//
// 这条是给"怕误用"的消费方看的：最常见的误用是宿主把 node 的退出码
// 改写成自己的口径（一律 0、或一律 1）—— 那调用方就失去了"靠退出码
// 判定成败/分区失败原因"的能力，CI 里尤其致命。
// 正确做法：node 返回什么，宿主就传什么。
console.log('HOST-EXIT-CODE7: exiting with code 7 on purpose');
process.exit(7);
