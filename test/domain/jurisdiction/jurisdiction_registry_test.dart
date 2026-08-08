// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:easa_digital_log/domain/jurisdiction/jurisdiction_profile.dart';
import 'package:easa_digital_log/domain/jurisdiction/jurisdiction_registry.dart';
import 'package:flutter_test/flutter_test.dart';

/// A synthetic three-generation lineage — not real regulatory data, just
/// enough to prove `extends` resolution actually walks the chain and lets a
/// child's own rules win. The real profiles (eu.easa.part-fcl,
/// us.faa.part61) don't extend anything yet, so this is the only place the
/// mechanism itself is exercised until a real UK CAA profile lands.
const _root = JurisdictionProfile(
  id: 'test.root',
  rules: {'pic_rule': 'root.pic', 'night_rule': 'root.night'},
);

const _middle = JurisdictionProfile(
  id: 'test.middle',
  extendsId: 'test.root',
  rules: {'night_rule': 'middle.night'},
);

const _leaf = JurisdictionProfile(
  id: 'test.leaf',
  extendsId: 'test.middle',
  rules: {'pic_rule': 'leaf.pic'},
);

void main() {
  group('JurisdictionRegistry.resolve', () {
    test('a root profile with no extends resolves to its own rules', () {
      final registry = JurisdictionRegistry([_root]);
      final resolved = registry.resolve('test.root');

      expect(resolved.id, 'test.root');
      expect(resolved['pic_rule'], 'root.pic');
      expect(resolved['night_rule'], 'root.night');
    });

    test('a middle profile inherits what it does not override', () {
      final registry = JurisdictionRegistry([_root, _middle]);
      final resolved = registry.resolve('test.middle');

      expect(resolved['pic_rule'], 'root.pic', reason: 'inherited from root');
      expect(resolved['night_rule'], 'middle.night', reason: 'overridden');
    });

    test('a three-generation chain merges root-first so the leaf wins', () {
      final registry = JurisdictionRegistry([_root, _middle, _leaf]);
      final resolved = registry.resolve('test.leaf');

      expect(resolved['pic_rule'], 'leaf.pic', reason: 'leaf overrides root');
      expect(
        resolved['night_rule'],
        'middle.night',
        reason: 'leaf does not override night_rule, so middle wins over root',
      );
    });

    test('an unset rule name resolves to null, not a missing-key throw', () {
      final registry = JurisdictionRegistry([_root]);
      final resolved = registry.resolve('test.root');

      expect(resolved['cross_country_rule'], isNull);
    });

    test('resolving an unregistered id throws ArgumentError naming it', () {
      final registry = JurisdictionRegistry([_root]);
      expect(
        () => registry.resolve('does.not.exist'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.toString(),
            'message',
            contains('does.not.exist'),
          ),
        ),
      );
    });

    test('resolving a profile whose extends target is missing throws', () {
      final registry = JurisdictionRegistry([_leaf]); // no root or middle
      expect(
        () => registry.resolve('test.leaf'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'an inheritance cycle throws StateError rather than looping forever',
      () {
        const cycleA = JurisdictionProfile(
          id: 'cycle.a',
          extendsId: 'cycle.b',
          rules: {},
        );
        const cycleB = JurisdictionProfile(
          id: 'cycle.b',
          extendsId: 'cycle.a',
          rules: {},
        );
        final registry = JurisdictionRegistry([cycleA, cycleB]);

        expect(() => registry.resolve('cycle.a'), throwsA(isA<StateError>()));
      },
    );
  });
}
