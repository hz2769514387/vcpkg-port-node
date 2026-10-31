// An uncaught exception is a failure, not a crash: the runtime has to report it on stderr
// and leave the host with exit code 1, exactly as node.exe does. Anything else - a hang, a
// code 0, an abort - means the embedding is not faithful.
throw new Error('intentional, to check the exit code');
