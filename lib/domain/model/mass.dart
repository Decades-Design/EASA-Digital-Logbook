/// A certificated mass, held in the unit it was certificated in.
///
/// **The unit is part of the fact, not a presentation choice.** Both
/// authorities draw sharp thresholds in their own units — `§61.31` and the
/// type-rating rule at more than 12,500 lb, EASA at 5,700 kg — and no single
/// storage unit is exact for both. 12,500 lb is 5669.904625 kg, so an aircraft
/// certificated at exactly 12,500 lb stored as 5670 kg converts back to
/// 12,500.2 lb and wrongly clears a threshold it sits precisely on. That
/// figure is a very common certification limit, chosen *because* it is the
/// threshold, so the error would be common too.
///
/// Keeping the certificated figure and its unit makes the comparison exact
/// whenever the threshold is expressed in the same unit, which is the case
/// that matters.
library;

/// The unit a mass was certificated in.
enum MassUnit { kilograms, pounds }

/// A mass as it appears on a type certificate.
class Mass implements Comparable<Mass> {
  const Mass(this.value, this.unit);

  const Mass.kilograms(int value) : this(value, MassUnit.kilograms);
  const Mass.pounds(int value) : this(value, MassUnit.pounds);

  /// The certificated figure, in [unit]. Whole units: no type certificate
  /// expresses a maximum takeoff mass to a finer resolution than this.
  final int value;

  final MassUnit unit;

  /// One pound in micrograms, exactly. The international avoirdupois pound is
  /// defined as exactly 0.45359237 kg, so this conversion is not an
  /// approximation and the arithmetic below stays in integers.
  static const int _microgramsPerPound = 453592370;
  static const int _microgramsPerKilogram = 1000000000;

  int get _micrograms => switch (unit) {
    MassUnit.kilograms => value * _microgramsPerKilogram,
    MassUnit.pounds => value * _microgramsPerPound,
  };

  /// Whether this mass is strictly greater than [threshold].
  ///
  /// Exact. When both are in the same unit it is an integer comparison; when
  /// they differ it is an integer comparison in micrograms, which the
  /// definition of the pound makes lossless.
  bool exceeds(Mass threshold) => _micrograms > threshold._micrograms;

  @override
  int compareTo(Mass other) => _micrograms.compareTo(other._micrograms);

  bool operator <(Mass other) => compareTo(other) < 0;
  bool operator <=(Mass other) => compareTo(other) <= 0;
  bool operator >(Mass other) => compareTo(other) > 0;
  bool operator >=(Mass other) => compareTo(other) >= 0;

  /// Equal when they represent the same mass, whatever unit each is held in.
  @override
  bool operator ==(Object other) =>
      other is Mass && other._micrograms == _micrograms;

  @override
  int get hashCode => _micrograms.hashCode;

  @override
  String toString() => switch (unit) {
    MassUnit.kilograms => '$value kg',
    MassUnit.pounds => '$value lb',
  };
}
