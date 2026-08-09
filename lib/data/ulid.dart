import 'dart:math';

/// Generates a [ULID](https://github.com/ulid/spec): a 26-character
/// Crockford base32 string encoding a 48-bit millisecond UTC timestamp
/// followed by 80 bits of randomness.
///
/// Used as the primary key for every table in `lib/data/` instead of an
/// autoincrement integer — see the "Identifiers" section of
/// `docs/superpowers/specs/2026-08-09-m2-flight-persistence-design.md`.
/// Two offline devices can each mint an id with no coordination and no
/// collision, which an autoincrement integer cannot offer once multi-device
/// sync exists (ADR-0005: sync is an additive layer, not being built yet,
/// but the ID scheme has to be right from the first row ever written).
///
/// [now] and [random] are injectable for deterministic tests only —
/// production call sites pass neither.
String generateUlid({DateTime? now, Random? random}) {
  final millis = (now ?? DateTime.now().toUtc()).millisecondsSinceEpoch;
  final rand = random ?? Random.secure();

  final chars = List<String>.filled(26, '0');
  var time = millis;
  for (var i = 9; i >= 0; i--) {
    chars[i] = _crockford[time & 0x1F];
    time >>= 5;
  }
  for (var i = 10; i < 26; i++) {
    chars[i] = _crockford[rand.nextInt(32)];
  }

  return chars.join();
}

/// Crockford's base32 alphabet: excludes I, L, O, U to avoid visual
/// confusion with 1, 1, 0, V.
const String _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
