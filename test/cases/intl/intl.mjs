// Locale data, calendars, collation and segmentation that only full ICU delivers, plus
// Temporal, which is implemented by the Rust crate in deps/crates and is absent when that
// crate was not built into libnode.
//
// Non-ASCII text is written with escapes: every tracked file in this repository is ASCII,
// and a literal character here would break the language gate rather than test ICU.
import assert from 'node:assert/strict';

const { versions, config } = process;
assert.equal(config.variables.icu_small, false, 'this is a small-icu build');
assert.equal(config.variables.icu_system, true);
assert.ok(Number(versions.icu) >= 70);
assert.equal(typeof Intl.Segmenter, 'function');
assert.equal(typeof Temporal, 'object');

// Known answers, pinned to the ICU version this port installs. A build with the small
// subset returns an en-US fallback for these locales instead of the localized form.
assert.equal(new Intl.NumberFormat('de-DE').format(1234.5), '1.234,5');
assert.equal(new Intl.DateTimeFormat('de-DE', { dateStyle: 'full', timeZone: 'UTC' })
  .format(new Date('2026-01-02T03:04:05Z')), 'Freitag, 2. Januar 2026');
assert.match(new Intl.NumberFormat('en-US', { style: 'currency', currency: 'EUR' })
  .format(42), /42/);

const calendars = Intl.supportedValuesOf('calendar');
assert.ok(calendars.includes('gregory'));
assert.ok(calendars.includes('japanese'));
assert.ok(Intl.supportedValuesOf('currency').includes('EUR'));

// Collation and segmentation exercise the data tables, not just the formatting tables.
assert.ok(new Intl.Collator('de-DE').compare('a', 'z') < 0);
const words = [...new Intl.Segmenter('en', { granularity: 'word' })
  .segment('three separate words')].filter((part) => part.isWordLike);
assert.equal(words.length, 3);

// A non-Latin string through the segmenter: the escaped code points spell a greeting in
// Japanese, and a full ICU build segments it into more than one word-like unit.
const japanese = '\u3053\u3093\u306b\u3061\u306f\u4e16\u754c';
const segments = new Intl.Segmenter('ja', { granularity: 'word' }).segment(japanese);
assert.ok(segments.containing(0));
assert.ok([...segments].length > 1, 'a CJK string was not segmented at all');

assert.equal(new Intl.Locale('de-DE-u-co-phonebk').collation, 'phonebk');
assert.equal(new Intl.DateTimeFormat('en-US', { timeZone: 'UTC', calendar: 'japanese' })
  .resolvedOptions().calendar, 'japanese');

// Temporal: the crate is a separate gyp target on this port, and on Linux it was once
// missing from the install entirely while every other assertion still passed.
assert.equal(Temporal.Duration.from('PT1H30M').total({ unit: 'minute' }), 90);
assert.ok(Temporal.Now.instant().epochNanoseconds > 0n);
assert.equal(Temporal.Instant.fromEpochMilliseconds(0).toZonedDateTimeISO('UTC').year, 1970);
assert.equal(Temporal.PlainDate.from('2026-01-02').add({ days: 28 }).day, 30);

console.log(`intl: full ICU ${versions.icu} and Temporal ok`);
