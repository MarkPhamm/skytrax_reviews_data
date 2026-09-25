{{ config(alias='dim_aircraft') }}

-- dim_aircraft.sql
-- Aircraft dimension for the seat review star schema.
-- Grain: one row per distinct aircraft model string found in the seat reviews.
-- Surrogate key: dbt_utils hash of the model string, so a given model string
-- carries the same key here as it does in the airline review mart.
-- Capacity comes from the same canonical family list used elsewhere.

with reviews as (

    select
        *,
    from {{ ref('int_seat_reviews_cleaned') }}

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
