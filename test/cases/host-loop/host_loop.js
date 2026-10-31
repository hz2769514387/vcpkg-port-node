// Records which host-driven uv_run iteration the timer fired in.
//
// The host stamps globalThis.__node_port_host_iteration before every pump, so the value seen
// here proves the callback executed inside the host's own uv_run call rather than during
// environment setup or on some other thread.
globalThis.__node_port_fired_at = undefined;

setTimeout(() => {
  globalThis.__node_port_fired_at = globalThis.__node_port_host_iteration;
  console.log(
    `script: timer fired in host iteration ${globalThis.__node_port_host_iteration}`,
  );
}, 20);
