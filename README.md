# Skytrax Reviews — Four-Subject Data Models (DuckDB)

Downloads the four Skytrax review tables straight from the source database and models **all four** of them into star schemas with dbt on DuckDB — no warehouse, no cloud account, one command.

> **Source status:** [AirlineQuality.com](https://www.airlinequality.com/) (Skytrax) is **permanently closed**. These are historical tables collected while the site was live, replayed from a SQL Server archive — not an ongoing feed.

[Part 2](https://github.com/MarkPhamm/skytrax_reviews_transformation) models **airline** reviews into a Kimball star schema on Snowflake, with slim CI/CD, Terraform RBAC and hosted docs. The seat, lounge and airport reviews have been sitting in `RAW` unmodelled the whole time — the umbrella repo lists *"conformed facts for seat / lounge / airport review types"* as a next step. This repo is that next step, done locally: **214,335 fact rows across four star schemas**, built and tested in under ten seconds on a laptop.

- **Four independent star schemas** — airline, airport, lounge and seat reviews, each with its own conformed dimensions, each exported as CSVs you can hand to anyone
- **Zero infrastructure** — dbt-duckdb reads the CSVs in place with `read_csv`; nothing is loaded anywhere first, no credentials needed to build
- **Same modelling conventions as Part 2** — staging → intermediate → marts, `dbt_utils` surrogate keys, incremental merge facts on a high-water mark, generated calendar/fiscal date dimension
- **Real duplicates caught** — unlike Part 2's source, these tables ship a `review_id`, and the scrape re-issues it on re-ingest. Deduplicating on that id alone would keep 346 re-ingested submissions, so staging dedupes on review *content* — the same natural key Part 2 uses
- **224 tests on every build** — 222 pass, 2 warn on known source defects that are documented rather than silently dropped

## Where this fits

| Part | Repository | Warehouse | Review types modelled |
| --- | --- | --- | --- |
| 1 · Extract & Load | [skytrax_reviews_extract_load](https://github.com/MarkPhamm/skytrax_reviews_extract_load) | Snowflake `RAW` | all four (landed, unmodelled) |
| 2 · Transform & DataOps | [skytrax_reviews_transformation](https://github.com/MarkPhamm/skytrax_reviews_transformation) | Snowflake `MARTS` | airline only |
| — · **This repo** | **skytrax_reviews_data** | **DuckDB (local file)** | **airline · airport · lounge · seat** |
| — · Umbrella | [skytrax_reviews](https://github.com/MarkPhamm/skytrax_reviews) | — | project narrative + dashboards |

> **Self-selection bias:** Skytrax reviews are self-reported. Passengers with extreme experiences are more likely to post, so any KPI built on these models is *directional*, not population-level.

## Architecture

```text
        ┌────────────────────────────┐
        │  Xóm Dataset SQL Server    │
        │  [skytrax] schema          │
        └─────────────┬──────────────┘
                      │ download.py (pytds)
                      ▼
        ┌────────────────────────────┐
        │  data/raw/*.csv            │
        │  4 review tables +         │
        │  airlines / airports lookup│
        └─────────────┬──────────────┘
                      │ dbt source (read_csv, in place)
                      ▼
        ┌────────────────────────────┐
        │  staging schema            │
        │  stg_skytrax__* (views)    │
        │  dedup on review content   │
        └─────────────┬──────────────┘
                      │
                      ▼
        ┌────────────────────────────┐
        │  intermediate schema       │
        │  int_*_cleaned (views)     │
        │  nulls → 'unknown', casts  │
        └─────────────┬──────────────┘
                      │
      ┌───────────┬───┴───────┬───────────┐
      ▼           ▼           ▼           ▼
 ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐
 │airlines_│ │airport_ │ │lounge_  │ │seat_    │
 │reviews  │ │reviews  │ │reviews  │ │reviews  │
 │ 5 dims  │ │ 3 dims  │ │ 4 dims  │ │ 5 dims  │
 │ + fct   │ │ + fct   │ │ + fct   │ │ + fct   │
 └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘
      │           │           │           │
      └───────────┴─────┬─────┴───────────┘
                        │ post-hook: COPY … TO csv
                        ▼
        ┌────────────────────────────┐
        │  data/<subject>_model/*.csv│
        │  + skytrax_reviews.duckdb  │
        └────────────────────────────┘
```

## Stack

| Layer | Technology |
| --- | --- |
| Extract | Python 3.12, python-tds, pandas |
| Storage | CSV on disk + a single DuckDB file |
| Transformation | dbt Core (dbt-duckdb), dbt_utils |
| Export | DuckDB `COPY … TO` via a dbt post-hook |
| Language | SQL, Python, Jinja |

Everything runs on a laptop. There is no warehouse, no cloud account, and no credentials required to build the models — only to re-download the raw data.

## Data Model

Four **independent** star schemas, one per review subject. Each carries its own copy of every dimension it needs, so a directory can be shipped and queried standalone. Where a dimension appears in more than one model (`dim_airline`, `dim_aircraft`, `dim_customer`) the definition and the keys are identical, so the models can also be joined across subjects.

**Grain:** one row per review submission. Primary key is `review_id` from the source.

### `data/airlines_reviews_model/` — 156,077 reviews, 2002–2026

| Model | Type | Rows | Description |
| --- | --- | ---: | --- |
| `fct_airline_review` | Fact (incremental merge) | 156,077 | 7 category ratings, `average_rating`, `rating_band`, `has_layover`, FKs to all dims |
| `dim_airline` | Dimension | 595 | Airline name + cleaned name |
| `dim_customer` | Dimension | 115,808 | Reviewer proxy, review count, first/latest review date |
| `dim_location` | Dimension | 5,973 | City + IATA code (role-playing: origin / destination / transit) |
| `dim_aircraft` | Dimension | 227 | Model, manufacturer, seat capacity |
| `dim_date` | Dimension | 9,399 | Calendar + fiscal (role-playing: submitted / flown) |

### `data/airport_reviews_model/` — 49,410 reviews, 2002–2026

| Model | Type | Rows | Description |
| --- | --- | ---: | --- |
| `fct_airport_review` | Fact (incremental merge) | 49,410 | 8 category ratings, `average_rating`, `rating_band`, `experience_at_airport` |
| `dim_airport` | Dimension | 1,004 | Airport name + cleaned name |
| `dim_customer` | Dimension | 38,101 | Reviewer proxy |
| `dim_date` | Dimension | 9,399 | Calendar + fiscal (role-playing: submitted / visited) |

### `data/lounge_reviews_model/` — 5,085 reviews, 2006–2026

| Model | Type | Rows | Description |
| --- | --- | ---: | --- |
| `fct_lounge_review` | Fact (incremental merge) | 5,085 | 7 category ratings, `average_rating`, `rating_band` |
| `dim_lounge` | Dimension | 2,220 | Lounge, airport, access tier (tier is part of the grain) |
| `dim_airline` | Dimension | 595 | Airline operating the lounge |
| `dim_customer` | Dimension | 3,241 | Reviewer proxy |
| `dim_date` | Dimension | 7,938 | Calendar + fiscal (role-playing: submitted / visited) |

### `data/seat_reviews_model/` — 3,763 reviews, 2007–2026

| Model | Type | Rows | Description |
| --- | --- | ---: | --- |
| `fct_seat_review` | Fact (incremental merge) | 3,763 | 12 category ratings, `average_rating`, `rating_band` |
| `dim_seat_configuration` | Dimension | 72 | Cabin + normalized layout, parsed `seats_per_row` |
| `dim_aircraft` | Dimension | 64 | Model, manufacturer, seat capacity |
| `dim_airline` | Dimension | 595 | Airline |
| `dim_customer` | Dimension | 3,089 | Reviewer proxy |
| `dim_date` | Dimension | 21,087 | Calendar + fiscal (role-playing: submitted / flown) |

### Key conventions

- **Natural keys where the source has them.** `airline_id` and `airport_id` come from the lookup tables and are used directly; dimensions built from free text use a deterministic `dbt_utils.generate_surrogate_key` hash.
- **`dim_date` is derived, not hard-coded.** Each model's calendar spans the dates it actually contains, extended 12 months past the latest for forecasting headroom — so no fact row is ever dropped for falling outside it.
- **`'unknown'` over null.** Dimension-bearing text is coalesced in the intermediate layer, so every fact row resolves to a dimension row instead of vanishing on an inner join.
- **Sparse ratings are respected.** `average_rating` divides by the number of categories the reviewer actually scored, not by the number of columns — a review that only rates value-for-money is not punished for it.

### Schema Diagram

Column-level source text lives in [`data_model/schema.txt`](data_model/schema.txt). Paste it into [QuickDBD](https://www.quickdatabasediagrams.com/) to generate the ERD.

## Data Quality

Every invariant below is enforced on each build — **222 tests pass, 2 warn**. Nothing is dropped silently.

### Fixed in the models

| Issue | Detail | Fix |
| --- | --- | --- |
| Duplicate scrapes | The source re-issues `review_id` on re-ingest, so the same submission appears under several ids — verified identical on every other column, ratings never disagree | Staging deduplicates on reviewer + subject + date + review text, keeping the latest `updated_at`. Removed **246** airline, **95** airport, **3** seat, **2** lounge rows, guarded by a `unique_combination_of_columns` test |
| Seat layout spellings | `3x3`, `3-3`, `3X3`, `3*3`, `3 x 3` and `3×3` are the same cabin but became six dimension members | Normalized in the intermediate layer — `dim_seat_configuration` collapsed from **117 members to 72**, and `seats_per_row` now parses 45 of them |

### Known and left alone

| Issue | Scale | Why it stays |
| --- | --- | --- |
| `date_flown` after `date_submitted` | 41 airline reviews | Only the flight date is suspect; ratings and text are genuine → warn-level test |
| Epoch-sentinel `date_submitted` (1970-01-01) | 3 seat reviews | Same — kept and flagged so the count is visible rather than skewing a time series |
| High sparsity | aircraft unstated on **74%** of airline reviews, origin airport on **51%**, traveller type on **25%** | Genuine source gaps. They land on `'unknown'` dimension members — filter before using those dimensions |
| `average_rating` is null | 1.4% of airline, 10.2% of airport reviews | The reviewer scored no category at all; `rating_band` is `'unknown'` there |
| `recommended` contradicts ratings | ~1% of rows | Reviewer subjectivity, not a defect — both fields reported as given |
| `dim_customer` is a proxy | — | The source does not identify reviewers, and names are synthetic (`Susan Allen 2` appears under two nationalities). Keyed on (name, nationality); treat as a proxy, not a person |

Clean on arrival: all ratings within 1–5, every review FK resolves to its lookup, all airport codes well-formed, no future-dated submissions.

## Getting Started

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
./build.sh
```

That builds all four models and writes the CSVs. **No credentials are needed** — the raw CSVs in `data/raw/` are all the build reads.

### Re-downloading the raw data

Only needed to refresh from source. Set the `XOMDATA_*` variables in `.env` (see [`.env.example`](.env.example)), then:

```bash
.venv/bin/python download.py --list                    # show available schemas
.venv/bin/python download.py --schema skytrax -o data  # writes to data/skytrax/
```

`download.py` writes to `<output-dir>/<schema>/`, so move the CSVs into `data/raw/` or point the build at them:

```bash
SKYTRAX_RAW_DIR="$PWD/data/skytrax" ./build.sh
```

## Quick Reference

```bash
./build.sh                        # build all four models + export CSVs
./build.sh --full-refresh         # rebuild the incremental facts from scratch
./build.sh -s +tag:lounge_reviews # any dbt selector is passed straight through
./build.sh -s fct_seat_review     # one model and nothing else

# Query the models directly — every mart is its own schema
duckdb skytrax_reviews.duckdb -c "
  select a.airline_name, count(*) as reviews, round(avg(f.average_rating), 2) as avg_rating
  from airlines_reviews.fct_airline_review f
  join airlines_reviews.dim_airline a using (airline_id)
  group by 1 order by reviews desc limit 10"

# dbt directly (build.sh sets these for you)
cd dbt
export DBT_PROFILES_DIR=$PWD SKYTRAX_RAW_DIR=../data/raw SKYTRAX_EXPORT_ROOT=../data
dbt deps && dbt build
dbt docs generate && dbt docs serve
```

`build.sh` creates the export directories (DuckDB's `COPY` will not), points dbt at `data/raw`, runs `dbt deps` and `dbt build`, and leaves a queryable database at `skytrax_reviews.duckdb`.

## Directory Layout

```text
download.py                     Pull the [skytrax] schema from SQL Server as CSV
build.sh                        Create export dirs, set env, run dbt, report output
dbt/
  models/
    staging/                    stg_skytrax__*  views over data/raw/*.csv, deduplicated
    intermediate/               int_*_cleaned   null handling, renames, type casts
    marts/
      airlines_reviews/         dim_airline, dim_customer, dim_location,
                                dim_aircraft, dim_date, fct_airline_review
      airport_reviews/          dim_airport, dim_customer, dim_date,
                                fct_airport_review
      lounge_reviews/           dim_airline, dim_lounge, dim_customer, dim_date,
                                fct_lounge_review
      seat_reviews/             dim_airline, dim_aircraft, dim_seat_configuration,
                                dim_customer, dim_date, fct_seat_review
  macros/
    aircraft.sql                Manufacturer parsing + fuzzy capacity lookup
    clean_airline_name.sql      Airline name normalization
    seat_layout.sql             Layout normalization + seats-per-row parsing
    ratings.sql                 average_rating, rating_band, rating validation
    generate_dates_dimension.sql  Calendar + fiscal dimension, bounds-derived
    export_model_to_csv.sql     The post-hook that writes the CSVs
    generate_schema_name.sql    Custom schema names used verbatim
  tests/                        Warn-level tests for known source defects
  profiles.yml                  DuckDB connection (env vars, no credentials)
data/
  raw/                          Input CSVs from download.py
  airlines_reviews_model/       Exported star schema, one CSV per model
  airport_reviews_model/
  lounge_reviews_model/
  seat_reviews_model/
data_model/schema.txt           Column-level reference for all four models
```

Model file names are prefixed with their mart (`airlines_reviews__dim_customer`) because dbt model names must be globally unique; each sets `alias` back to the plain name, so the relation and the exported CSV are `dim_customer`.

## Environment Variables

| Variable | Used by | Default | Purpose |
| --- | --- | --- | --- |
| `SKYTRAX_RAW_DIR` | dbt sources | `../data/raw` | Where the input CSVs are read from |
| `SKYTRAX_EXPORT_ROOT` | export post-hook | `../data` | Parent of the four output directories |
| `SKYTRAX_DUCKDB_PATH` | dbt profile | `../skytrax_reviews.duckdb` | Database file location |
| `XOMDATA_*` | `download.py` only | — | SQL Server connection; not needed to build |

## Notes

The exported CSVs are gitignored — `fct_airline_review.csv` alone is 167 MB, past GitHub's file limit. Clone and run `./build.sh` to regenerate them in a few seconds, or export to Parquet if you need to ship them — that same fact is 46 MB as Parquet, comfortably under the limit.

---

*Skytrax Global Airlines Analytics Project*
