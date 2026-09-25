# skytrax_reviews_data

Downloads the Skytrax review tables from the Xóm Dataset SQL Server and models
them into four dimensional (star schema) data models with dbt on DuckDB, each
exported back out as CSVs.

```
data/
  raw/                        # what download.py pulls down
    airline_reviews.csv  airlines.csv
    airport_reviews.csv  airports.csv
    lounge_reviews.csv   seat_reviews.csv
  airlines_reviews_model/     # dim_* + fct_airline_review as CSV
  airport_reviews_model/      # dim_* + fct_airport_review as CSV
  lounge_reviews_model/       # dim_* + fct_lounge_review as CSV
  seat_reviews_model/         # dim_* + fct_seat_review as CSV
```

The modelling approach mirrors `../skytrax_reviews_transformation`
(staging -> intermediate -> marts, surrogate keys via `dbt_utils`, incremental
merge facts, a generated date dimension), but runs on the **dbt-duckdb** adapter
against the local CSVs instead of Snowflake.

## Setup

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

## Download the raw data

Set the `XOMDATA_*` connection variables in `.env`, then:

```bash
.venv/bin/python download.py --schema skytrax --output-dir data
```

`download.py` writes to `<output-dir>/<schema>/`, so that lands the CSVs in
`data/skytrax/`. The build reads from `data/raw/` by default - either move them
there, or point the build at wherever they are:

```bash
SKYTRAX_RAW_DIR="$PWD/data/skytrax" ./build.sh
```

## Build the data models

```bash
./build.sh                       # build everything and export the CSVs
./build.sh --full-refresh        # rebuild the incremental facts from scratch
./build.sh -s +tag:lounge_reviews   # any dbt selector is passed straight through
```

`build.sh` creates the export directories (DuckDB's `COPY` will not), points dbt
at `data/raw`, runs `dbt deps` and `dbt build`, and leaves a queryable DuckDB
database at `skytrax_reviews.duckdb`:

```bash
duckdb skytrax_reviews.duckdb -c "select * from airlines_reviews.fct_airline_review limit 5"
```

Every mart model carries a `post-hook` that copies its table to
`data/<subject>_reviews_model/<relation>.csv`, so the CSVs are refreshed on
every build.

## Layout

```
dbt/
  models/
    staging/        stg_skytrax__*      views over data/raw/*.csv, deduped on review_id
    intermediate/   int_*_cleaned       null handling, renames, type casts
    marts/
      airlines_reviews/   dim_airline, dim_customer, dim_location,
                          dim_aircraft, dim_date, fct_airline_review
      airport_reviews/    dim_airport, dim_customer, dim_date,
                          fct_airport_review
      lounge_reviews/     dim_airline, dim_lounge, dim_customer, dim_date,
                          fct_lounge_review
      seat_reviews/       dim_airline, dim_aircraft, dim_seat_configuration,
                          dim_customer, dim_date, fct_seat_review
  macros/
    aircraft.sql                 manufacturer parsing + fuzzy capacity lookup
    clean_airline_name.sql       airline name normalization
    export_model_to_csv.sql      the post-hook that writes the CSVs
    generate_dates_dimension.sql calendar + fiscal date dimension
    ratings.sql                  average_rating, rating_band, rating validation
    generate_schema_name.sql     custom schema names used verbatim
data_model/schema.txt            column-level reference for all four models
```

Model file names are prefixed with their mart (`airlines_reviews__dim_customer`)
because dbt model names must be globally unique; each sets `alias` back to the
plain name, so the relation and the exported CSV are `dim_customer`.

## Conventions

* Fact grain is one row per review; the primary key is the source `review_id`.
* Dimensions with a stable source id (`airline_id`, `airport_id`) use it
  directly; dimensions derived from free text use a deterministic
  `dbt_utils.generate_surrogate_key` hash.
* `dim_date` is keyed on the date itself and spans the dates actually present in
  that model, so no fact row is ever dropped for falling outside the calendar.
* Dimension-bearing text is coalesced to `'unknown'` in the intermediate layer,
  so every fact row resolves to a dimension row.
* Ratings are 1-5 and nullable; `average_rating` is the mean of the categories
  the reviewer actually scored, and `rating_band` buckets it into
  `bad` / `medium` / `good` / `unknown`.
* Facts are incremental (`merge` on `review_id`) with a pure high-water mark on
  `source_updated_at`.

## Data quality

What the source data looks like, and what the models do about it. `./build.sh`
enforces all of this on every run (253 passing tests, 2 expected warnings).

**Fixed in the models**

* *Duplicate scrapes.* The source re-issues `review_id` when it re-ingests a
  review, so the same submission appears under several ids - identical on every
  other column. Staging deduplicates on the content that actually identifies a
  submission (reviewer, subject, date, review text) and keeps the most recently
  updated copy. Removed: 246 airline, 95 airport, 3 seat, 2 lounge rows.
  A `unique_combination_of_columns` test on each staging model guards this.
* *Seat layout spellings.* `3x3`, `3-3`, `3X3`, `3*3`, `3 x 3` and `3×3` are the
  same cabin. They are normalized in the intermediate layer, which collapsed
  `dim_seat_configuration` from 117 members to 72.

**Known and left alone** (flagged by warn-level tests, or documented here)

* 41 airline reviews have a `date_flown` *after* `date_submitted`; 3 seat
  reviews carry an epoch-sentinel `date_submitted` of 1970-01-01. The ratings
  and review text are genuine, so the rows are kept and warned on rather than
  dropped - see `dbt/tests/`.
* Sparsity is high on the airline fact and drives a lot of `'unknown'`
  dimension members: aircraft is unstated on 74% of reviews, origin airport on
  51%, traveller type on 25%. Filter these out before using those dimensions.
* `average_rating` is null where the reviewer scored no category at all: 1.4% of
  airline reviews, 10.2% of airport reviews. `rating_band` is `'unknown'` there.
* `recommended` disagrees with the ratings on roughly 1% of rows (recommended
  despite a bad average, or vice versa). That is reviewer subjectivity, not a
  defect - both fields are reported as given.
* `dim_customer` is keyed on (name, nationality) because the source does not
  identify reviewers. The names are clearly synthetic (`Susan Allen 2` appears
  under two nationalities), so treat it as a proxy, not a person.
* Ratings are all within 1-5 and every review FK resolves to its lookup, so
  there is no referential damage in the source.

The four models are independent - each directory carries every dimension it
needs and can be read standalone - but shared dimensions use identical
definitions and keys, so they can also be joined across subjects.
