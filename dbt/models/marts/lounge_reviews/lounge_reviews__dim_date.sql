{{ config(alias='dim_date') }}

-- dim_date.sql
-- Conformed date dimension for the lounge review star schema.
-- Grain: one row per calendar day.
-- Key: date_id (the date itself).

{{ generate_dates_dimension(
    ref('int_lounge_reviews_cleaned'),
    ['date_submitted', 'date_visit']
) }}
