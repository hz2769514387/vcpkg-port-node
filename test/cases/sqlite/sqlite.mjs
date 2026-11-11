// The SQL a real application writes, against the sqlite3 the port installed.
//
// Every statement below depends on a compile-time option the registry's default sqlite3
// does not always enable. If any one of them is missing, the failure is a syntax error in
// a consumer's query, not a link error at build time.
import assert from 'node:assert/strict';
import { DatabaseSync, StatementSync } from 'node:sqlite';

const db = new DatabaseSync(':memory:');
assert.ok(db instanceof DatabaseSync);
assert.match(db.prepare('select sqlite_version() AS v').get().v, /^3[.]/);

// FTS5 with a MATCH query and a rank, then a prepared statement with a bound parameter.
db.exec('CREATE VIRTUAL TABLE docs USING fts5(title, body)');
const insert = db.prepare('INSERT INTO docs (title, body) VALUES (?, ?)');
insert.run('first', 'the quick brown fox');
insert.run('second', 'a slow green turtle');
assert.ok(insert instanceof StatementSync);
assert.equal(db.prepare('SELECT title FROM docs WHERE docs MATCH ?').get('quick').title, 'first');
assert.equal(db.prepare('SELECT count(*) AS n FROM docs').get().n, 2);

// JSON1: extracting from a JSON document stored as text.
db.exec('CREATE TABLE events (id INTEGER PRIMARY KEY, payload TEXT)');
db.prepare('INSERT INTO events (payload) VALUES (?)').run('{"kind":"click","count":7}');
assert.equal(db.prepare("SELECT json_extract(payload, '$.count') AS c FROM events").get().c, 7);
assert.equal(db.prepare("SELECT json_valid(payload) AS ok FROM events").get().ok, 1);

// Math functions (SQLITE_ENABLE_MATH_FUNCTIONS) and a user-defined function, which is how
// an application extends SQL from JavaScript.
assert.equal(db.prepare('SELECT pow(2, 10) AS p').get().p, 1024);
assert.equal(Math.round(db.prepare('SELECT sin(pi() / 2) AS s').get().s), 1);
db.function('double_it', (n) => n * 2);
assert.equal(db.prepare('SELECT double_it(21) AS d').get().d, 42);

// R*Tree (SQLITE_ENABLE_RTREE): a spatial index rather than a plain table.
db.exec('CREATE VIRTUAL TABLE boxes USING rtree(id, minX, maxX, minY, maxY)');
db.exec('INSERT INTO boxes VALUES (1, 0, 10, 0, 10), (2, 20, 30, 20, 30)');
assert.equal(db.prepare('SELECT count(*) AS n FROM boxes WHERE minX <= 5 AND maxX >= 5').get().n, 1);

// Transactions and iterators: the parts of DatabaseSync a service uses per request.
db.exec('CREATE TABLE ledger (n INTEGER)');
const tx = db.prepare('INSERT INTO ledger (n) VALUES (?)');
db.exec('BEGIN');
for (let n = 0; n < 5; n += 1) tx.run(n);
db.exec('COMMIT');
assert.equal([...db.prepare('SELECT n FROM ledger ORDER BY n').iterate()]
  .reduce((sum, row) => sum + row.n, 0), 10);

db.close();
console.log('sqlite: feature surface ok');
