// beforeExit is allowed to add work to the loop. Node.js emits it again once that work is
// done, so two emissions is the correct result and one would mean the host drained the loop
// without letting Node.js schedule from its own hooks.
let emissions = 0;
process.on('beforeExit', () => {
  emissions += 1;
  console.log(`before-exit-${emissions}`);
  if (emissions === 1) setTimeout(() => {}, 10);
});
console.log('body-ran');
