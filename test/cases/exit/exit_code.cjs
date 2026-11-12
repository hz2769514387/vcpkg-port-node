// process.exitCode is the polite way out: the loop drains, beforeExit fires, and the exit
// hooks see the code the script chose rather than zero.
process.on('exit', (code) => console.log(`exit-hook-${code}`));
process.on('beforeExit', () => console.log('before-exit-ran'));
process.exitCode = 9;
console.log('body-ran');
