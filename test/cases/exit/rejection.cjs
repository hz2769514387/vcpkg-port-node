// The same script under --unhandled-rejections=strict (fatal, exit 1) and
// --unhandled-rejections=warn (a warning, exit 0). One runtime, two policy decisions made
// by a command-line flag the host passed through.
Promise.reject(new Error('rejected'));
