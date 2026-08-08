# Aerodrome dataset

`airports.csv` — downloaded from [OurAirports](https://ourairports.com/data/airports.csv) on
2026-08-08.

**Licence:** OurAirports data is public domain
([ourairports.com/data](https://ourairports.com/data/)). No attribution is legally required; this
file records provenance anyway so the source is traceable if the data ever needs re-verifying or
re-downloading.

**Format:** one CSV, one row per aerodrome, header:

```
id, ident, type, name, latitude_deg, longitude_deg, elevation_ft, continent, iso_country,
iso_region, municipality, scheduled_service, icao_code, iata_code, gps_code, local_code,
home_link, wikipedia_link, keywords
```

Parsed by `lib/domain/model/aerodrome_directory.dart`. Only `icao_code`, `iata_code`, `name`,
`latitude_deg`, `longitude_deg`, `elevation_ft` and `iso_country` are used — see #14. A row with
both `icao_code` and `iata_code` blank is skipped: those fields are the only public identifiers
the app looks aerodromes up by, and OurAirports carries thousands of closed strips and heliports
identified only by an internal `gps_code`/`local_code`.

**Unfiltered, ~12 MB, ~85,800 rows.** Every entry worldwide, including closed and non-flying
types. Deliberately left as-is for now — see #106 for the decision to slim it down before a
release build, and how.
