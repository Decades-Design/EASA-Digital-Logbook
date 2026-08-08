# Aerodrome fixtures

Raw CSV, in OurAirports' own column format — unlike most of `test/fixtures/`, there is no YAML
wrapper here, because the thing under test is the CSV parser itself; wrapping the input in YAML
would add a translation step with nothing left to verify.

- `sample_ourairports.csv` — a handful of representative rows: full ICAO+IATA (JFK, LHR), an
  embedded comma inside a quoted `name` field (EWR, proving RFC4180 quoting is respected rather
  than a naive comma split), a heliport with neither code (skipped), an IATA-only strip (kept,
  not indexed by ICAO), a blank elevation, and an otherwise-valid row with unparseable
  coordinates (skipped).
- `duplicate_icao.csv` — two rows sharing one ICAO code, for the documented "later wins"
  behaviour of `AerodromeDirectory`.
- `missing_column.csv` — a header with `iso_country` removed, for the "reject rather than guess"
  path when the upstream column layout changes.
