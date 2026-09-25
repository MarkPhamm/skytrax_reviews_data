{{ config(alias='dim_date') }}

-- dim_date.sql
-- Conformed date dimension for the airline review star schema.
-- Grain: one row per calendar day.
-- Key: date_id (the date itself), so fact rows join on the raw date.
-- Range is derived from the dates present in this mart - see the
-- generate_dates_dimension macro.

{{ generate_dates_dimension(
    ref('int_airline_reviews_cleaned'),
    ['date_submitted', 'date_flown']
) }}
