// process.exit() has to stop the script at once. If the runtime merely set a flag and let
// the script continue, "unreachable" would be printed and check_exit.cmake would fail.
process.on('exit', (code) => console.log(`exit-hook-${code}`));
process.exit(5);
console.log('unreachable');
