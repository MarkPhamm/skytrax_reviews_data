{{ config(alias='dim_aircraft') }}

-- dim_aircraft.sql
-- Aircraft dimension.
-- Grain: one row per distinct aircraft model string found in the reviews.
-- Surrogate key: dbt_utils hash of the model string.
-- Capacity is enriched by fuzzy-matching the free-text model against a small
-- canonical family list (see the aircraft macros); the QUALIFY keeps the
-- longest - and therefore most specific - family match per model.

with reviews as (

    select
        *,
    from {{ ref('int_airline_reviews_cleaned') }}

),

raw_aircraft as (

    select distinct aircraft_model,
    from reviews

),

mapped as (

    {{ aircraft_family_seed() }}
),

final as (

    select
        {{ dbt_utils.generate_surrogate_key(['raw_aircraft.aircraft_model']) }} as aircraft_id,
        raw_aircraft.aircraft_model,
        {{ extract_aircraft_manufacturer('raw_aircraft.aircraft_model') }} as aircraft_manufacturer,
        mapped.capacity as seat_capacity,
    from raw_aircraft
    left join mapped
        on {{ fuzzy_match_aircraft_family('raw_aircraft.aircraft_model', 'mapped.model') }}
    qualify row_number() over (
            partition by raw_aircraft.aircraft_model
            order by length(mapped.model) desc nulls last
        ) = 1

)

select
    *,
from final
