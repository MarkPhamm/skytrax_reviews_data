{{ config(alias='dim_airline') }}

-- dim_airline.sql
-- Airline dimension for the seat review star schema.
-- Grain: one row per airline in the source airline lookup.
-- Key: airline_id straight from the source.

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
