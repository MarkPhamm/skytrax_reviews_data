{{ config(alias='dim_airline') }}

-- dim_airline.sql
-- Airline dimension.
-- Grain: one row per airline in the source airline lookup.
-- Key: airline_id straight from the source - it is a stable natural key, so
-- there is nothing to gain from hashing a surrogate on top of it.
-- Built from the full lookup rather than from the reviews, so airlines with no
-- reviews yet are still present in the dimension.

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
