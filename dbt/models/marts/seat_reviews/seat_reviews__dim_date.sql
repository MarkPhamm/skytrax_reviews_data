{{ config(alias='dim_date') }}

-- dim_date.sql
-- Conformed date dimension for the seat review star schema.
-- Grain: one row per calendar day.
-- Key: date_id (the date itself).
-- Note: a handful of seat reviews carry an epoch-sentinel date_submitted of
-- 1970-01-01. The calendar is derived from the observed bounds, so those rows
-- still resolve to a dimension row instead of being dropped as orphans.

{{ generate_dates_dimension(
    ref('int_seat_reviews_cleaned'),
    ['date_submitted', 'date_flown']
) }}
