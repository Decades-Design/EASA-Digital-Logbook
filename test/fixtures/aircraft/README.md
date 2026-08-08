# aircraft/

Aircraft definition fixtures — registration, make and model, category, engine,
operating surface, and **what the pilot has declared the aircraft requires**
under each authority.

**Qualifications are declared, not derived.** The pilot enters them; the app
does not work them out from physical attributes. See the `Aircraft` class
dartdoc for why — the short version is that vendor CSVs export `complex` as a
flag and physical attributes cannot be reconstructed from it, so a derived
model could never store what an import actually says.

`required_qualifications` is keyed by jurisdiction profile id. A **missing
key** means the aircraft has not been set up for that authority; a **present
but empty** list means it has, and requires nothing. Those are different
answers.

Simulators are not here — an FSTD is a separate model, because `AMC1 FCL.050`
column 11 makes a device session a distinct entry rather than a flight in a
different machine.

The set is chosen to pin the asymmetry between the two systems:

| Fixture | What it pins |
|---|---|
| `g_abcd` | The trainer `flights/faa_easa_divergence.yaml` references. Set up under both authorities, requiring nothing under either |
| `n456bd` | Two FAA endorsements and three EASA items from one aeroplane |
| `g_arrow` | Complex but **not** high performance — §3's first asymmetry case |
| `g_c206` | High performance but **not** complex — the exact mirror of the Arrow |
| `g_multicrew` | Type-rated on a shared identifier; FAA key **absent**, not empty |
| `g_tailwheel_tmg` | A non-aeroplane category, and the one qualification that maps across systems |

See `test/fixtures/README.md` for the loading convention and quoting rules.
