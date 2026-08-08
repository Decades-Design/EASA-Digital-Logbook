# malformed/

Deliberately broken aircraft fixtures. Each exercises a way the decoder must
fail loudly rather than quietly substituting a default or dropping a value.

They live in their own directory so nothing iterating `aircraft/` picks them up
as real aircraft, and so a reader who opens one knows the error is the point.
