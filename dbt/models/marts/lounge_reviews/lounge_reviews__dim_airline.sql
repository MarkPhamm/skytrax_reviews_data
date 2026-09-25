{{ config(alias='dim_airline') }}

-- dim_airline.sql
-- Airline dimension for the lounge review star schema.
-- Grain: one row per airline in the source airline lookup.
-- Key: airline_id straight from the source.
-- Same definition as the airline review mart's dim_airline - each star schema
-- keeps its own physical copy so it can be shipped and read standalone.

with airlines as (

    select
        *,
    from {{ ref('stg_skytrax__airlines') }}

),

final as (

    select
        airline_id,
        airline_name,
        {{ clean_airline_name('airline_name') }} as airline_name_cleaned,
    from airlines

)

select
    *,
from final
