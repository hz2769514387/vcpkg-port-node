// One number, on one line, for check_node_options.cmake to compare between two runs.
import v8 from 'node:v8';
console.log(v8.getHeapStatistics().heap_size_limit);
