# aircraft/

Aircraft definition fixtures — registration, make and model, category, engine,
operating surface, and the physical equipment each authority's rules read.

**Categories are never stored.** FAA complex, high-performance and technically
advanced (`§61.31`, `§61.129(j)`) and the EASA class rating are all *computed*
from the facts in these files. Each fixture's header comment records what the
derivations should produce, as a comment and never as a stored key — the same
convention `flights/` and `capacities/` use. See CLAUDE.md rule 1 and ADR-0001.

Simulators are **not** here. An FSTD is a separate model (`lib/domain/model/
fstd.dart`) because `AMC1 FCL.050` column 11 makes a device session a distinct
entry rather than a flight in a different machine. Device fixtures live in
`fstd/`.

The set is chosen so that no single derivation can be broken without a fixture
noticing:

| Fixture | What it pins |
|---|---|
| `g_abcd` | The plain trainer referenced by `flights/faa_easa_divergence.yaml`. All three FAA categories false |
| `n456bd` | All three true at once, so a primitive ignoring one condition fails |
| `g_seaplane` | Complex **without** retractable gear — `§61.31(e)` drops that condition for seaplanes |
| `g_multicrew` | Type-rated, multi-crew, and horsepower absent so high-performance is *unknown* rather than false |
| `g_tailwheel_tmg` | A non-aeroplane category, and tailwheel differences training |

See `test/fixtures/README.md` for the loading convention and quoting rules.
