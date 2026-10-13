// 场景③-a：脚本正常跑完 —— 宿主拿到的退出码必须是 0。
//
// 这个文件本身没什么可看的；值得看的是同目录的 check_exit.cmake：
// 它把"node 的退出码 == 宿主期望的值"这件事变成 ctest 能判定的结果。
console.log('HOST-EXIT-OK: script finished normally');
