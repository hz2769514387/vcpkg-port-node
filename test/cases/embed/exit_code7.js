// A host program often decides its own exit code from what the embedded runtime did.
// process.exitCode is the documented way for a script to ask for one, and the value has to
// survive all the way out through node::Start into the host's return code.
process.exitCode = 7;
console.log('host: asking for exit code 7');
