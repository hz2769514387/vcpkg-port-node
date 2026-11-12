// The child side of workers.child_process_ipc.
process.on('message', (message) => {
  if (message.value === 'stop') {
    process.disconnect();
    return;
  }
  process.send({ value: message.value * 2, from: 'ipc-child' });
});
