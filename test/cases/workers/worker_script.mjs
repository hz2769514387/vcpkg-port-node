// One member of the pool. It shares an Int32Array with the host and its two siblings.
import { parentPort, workerData } from 'node:worker_threads';

const { id, shared } = workerData;
const square = id * id;
Atomics.add(shared, 0, square);
parentPort.postMessage({ id, square });
