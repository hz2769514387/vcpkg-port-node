// 场景③-b：未捕获异常 —— node 的约定是退出码 1。
//
// 注意不是 0（失败被吞了），也不是崩溃码（段错误那类）：未捕获异常是
// "脚本失败"的正常表达方式，退出码 1。宿主侧、CI 侧都按 1 判定就行。
// （栈会打到 stderr，那是给开发者看的，不影响退出码语义。）
throw new Error('HOST-EXIT-UNCAUGHT: deliberate uncaught exception');
