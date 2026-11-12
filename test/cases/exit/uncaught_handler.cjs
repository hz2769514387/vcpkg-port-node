// An uncaughtException handler is a decision the script makes, not the runtime's default
// abort. The handler must see the error and be able to choose its own exit code.
process.on('uncaughtException', (error) => {
  console.log(`caught-${error.message}`);
  process.exit(3);
});
setImmediate(() => { throw new Error('boom'); });
