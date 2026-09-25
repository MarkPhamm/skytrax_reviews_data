{{ config(
    alias='fct_airline_review',
    materialized='incremental',
    unique_key='review_id',
    incremental_strategy='merge',
    on_schema_change='fail',
) }}

-- fct_airline_review.sql
-- Airline (flight) review fact.
-- Grain: one row per review submission.
-- Primary key: review_id, carried through from the source.
-- Every dimensional attribute is a foreign key to a conformed dimension; the
-- ratings and the derived average/band are the measures.
-- Incremental: merge on review_id, processing only rows whose source
-- updated_at is newer than the high-water mark already loaded. Pure HWM on
-- updated_at with no lookback, because late or corrected rows bump updated_at.
-- A lookback window would be needed if the filter were on event time
-- (date_submitted). Backfill with:
--   dbt run -s fct_airline_review --full-refresh

{% set rating_columns = [
    'seat_comfort',
    'cabin_staff_service',
    'food_and_beverages',
    'inflight_entertainment',
    'ground_service',
    'wifi_and_connectivity',
    'value_for_money',
] %}

with base as (

    select
        src.*,
    from {{ ref('int_airline_reviews_cleaned') }} as src
    {% if is_incremental() %}
        where src.updated_at > (
            select max(prev.source_updated_at)
            from {{ this }} as prev
        )
    {% endif %}

),

with_customer as (

    select
        b.*,
        dc.customer_id,
    from base as b
    left join {{ ref('airlines_reviews__dim_customer') }} as dc
        on b.customer_name = dc.customer_name
        and b.nationality = dc.nationality

),

with_dates as (

    select
        wc.*,
        ds.date_id as date_submitted_id,
        df.date_id as date_flown_id,
    from with_customer as wc
    left join {{ ref('airlines_reviews__dim_date') }} as ds
        on wc.date_submitted = ds.date_id
    left join {{ ref('airlines_reviews__dim_date') }} as df
        on wc.date_flown = df.date_id

),

with_locations as (

    select
        wd.*,
        lo_origin.location_id as origin_location_id,
        lo_dest.location_id as destination_location_id,
        lo_transit.location_id as transit_location_id,
    from with_dates as wd
    left join {{ ref('airlines_reviews__dim_location') }} as lo_origin
        on wd.origin_city = lo_origin.city
        and wd.origin_airport = lo_origin.airport
    left join {{ ref('airlines_reviews__dim_location') }} as lo_dest
        on wd.destination_city = lo_dest.city
        and wd.destination_airport = lo_dest.airport
    left join {{ ref('airlines_reviews__dim_location') }} as lo_transit
        on wd.transit_city = lo_transit.city
        and wd.transit_airport = lo_transit.airport

),

with_aircraft as (

    select
        wl.*,
        da.aircraft_id,
    from with_locations as wl
    left join {{ ref('airlines_reviews__dim_aircraft') }} as da
        on wl.aircraft_model = da.aircraft_model

),

with_ratings as (

    select
        wa.*,
        {{ average_rating(rating_columns) }} as average_rating,
    from with_aircraft as wa

),

final as (

    select
        review_id,
        airline_id,
        customer_id,
        date_submitted_id,
        date_flown_id,
        origin_location_id,
        destination_location_id,
        transit_location_id,
        aircraft_id,
        is_verified,
        seat_type,
        type_of_traveller,
        transit_city != 'unknown' as has_layover,
        seat_comfort,
        cabin_staff_service,
        food_and_beverages,
        inflight_entertainment,
        ground_service,
        wifi_and_connectivity,
        value_for_money,
        recommended,
        average_rating,
        {{ rating_band('average_rating') }} as rating_band,
        review_text,
        updated_at as source_updated_at,
        current_timestamp as dbt_loaded_at,
    from with_ratings
    where
        -- Drop rows whose mandatory foreign keys failed to resolve. date_flown
        -- and the location/aircraft keys are optional on the source, but the
        -- 'unknown' coalescing in the intermediate layer means they always
        -- resolve to a dimension row in practice - a null here is a real defect.
        customer_id is not null
        and date_submitted_id is not null
        and origin_location_id is not null
        and destination_location_id is not null
        and transit_location_id is not null
        and aircraft_id is not null
        -- Every rating is unscored (null) or a valid 1-5 score.
        and {{ valid_ratings_filter(rating_columns) }}

)

select
    *,
from final
