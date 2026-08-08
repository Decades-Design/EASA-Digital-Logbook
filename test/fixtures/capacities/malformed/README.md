# malformed/

Fixtures that are **deliberately broken**. Each one exercises a way the
decoder must fail loudly rather than quietly substituting a default.

They live in their own directory so nothing iterating `capacities/` picks them
up as real scenarios, and so a reader who opens one knows immediately that the
error is the point.
