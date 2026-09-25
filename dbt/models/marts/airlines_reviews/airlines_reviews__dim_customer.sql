{{ config(alias='dim_customer') }}

-- dim_customer.sql
-- Customer dimension for the airline review star schema.
-- Grain: one row per unique (customer_name, nationality) combination.
-- Surrogate key: dbt_utils hash of the natural key, so it is deterministic and
-- idempotent across full refreshes.
-- Note: reviewers are not identified in the source, so (name, nationality) is
-- the best available proxy for a person. Two different people sharing a name
-- and nationality collapse into one row.

with reviews as (

    select
        *,
    from {{ ref('int_airline_reviews_cleaned') }}

),

customer_agg as (

    select
        customer_name,
        nationality,
        count(*) as number_of_reviews,
        min(date_submitted) as first_review_date,
        max(date_submitted) as latest_review_date,
    from reviews
    group by
        customer_name,
        nationality

),

final as (

    select
        {{ dbt_utils.generate_surrogate_key(['customer_name', 'nationality']) }} as customer_id,
        customer_name,
        nationality,
        number_of_reviews,
        first_review_date,
        latest_review_date,
    from customer_agg

)

select
    *,
from final
