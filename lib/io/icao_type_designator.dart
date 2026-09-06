/// Whether [value] has the shape of a real ICAO aircraft type designator
/// (ICAO Doc 8643): two to four characters, letters and digits only, no
/// separators. A shape check, not a lookup against the actual registry — a
/// real but obscure type this app has never heard of still passes; this
/// exists to catch a vendor column that plainly isn't an ICAO code at all
/// (a full model name, a hyphenated variant suffix, embedded spaces), which
/// #74 requires be flagged rather than trusted or silently dropped.
bool looksLikeIcaoTypeDesignator(String value) =>
    RegExp(r'^[A-Z0-9]{2,4}$').hasMatch(value);
