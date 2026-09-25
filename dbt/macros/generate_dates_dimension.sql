{% macro generate_dates_dimension(source_relation, date_columns) %}
{#-
    Build a conformed date dimension for one mart.

    Rather than hard-coding a start date, the calendar is bounded by the dates
    actually present in that mart's reviews: it starts at the beginning of the
    earliest year observed and runs to 12 months past the later of the latest
    observed date and today (headroom for forecasting). That way every date
    foreign key resolves and no review row is dropped for falling outside the
    calendar.

    Fiscal year is assumed to start on 1 July.

    Args:
        source_relation: relation to read the date bounds from (e.g. ref('...'))
        date_columns: list of date column names in that relation
-#}

with bounds as (

    select
        -- least/greatest ignore nulls in DuckDB, so optional dates (date_flown,
        -- date_visit) widen the range when present and are harmless when not.
        least(
            {% for column in date_columns -%}
            min({{ column }}){{ ', ' if not loop.last }}
            {%- endfor %}
        ) as start_date,
        greatest(
            {% for column in date_columns -%}
            max({{ column }}){{ ', ' if not loop.last }}
            {%- endfor %}
        ) as end_date,
    from {{ source_relation }}

),

calendar as (

    select
        unnest(
            generate_series(
                date_trunc('year', bounds.start_date)::date,
                (greatest(bounds.end_date, current_date) + interval 12 month)::date,
                interval 1 day
            )
        )::date as date_id,
    from bounds

),

dates_fin as (

    select
        date_id,
        isodow(date_id) as day_of_week,                        -- 1 = Monday .. 7 = Sunday
        strftime(date_id, '%a') as day_of_week_name,
        date_trunc('week', date_id)::date as cal_week_start_date,  -- Monday start
        extract(day from date_id) as day_of_month,
        extract(month from date_id) as cal_month,
        strftime(date_id, '%B') as cal_mon_name,
        strftime(date_id, '%b') as cal_mon_name_short,
        extract(quarter from date_id) as cal_quarter,
        concat('Q', extract(quarter from date_id)) as cal_quarter_name,
        extract(year from date_id) as cal_year,
        isodow(date_id) in (6, 7) as is_weekend,
        case
            when extract(month from date_id) < 7 then extract(year from date_id)
            else extract(year from date_id) + 1
        end as fin_year,
        case
            when extract(month from date_id) < 7 then extract(month from date_id) + 6
            else extract(month from date_id) - 6
        end as fin_period,
        case
            when extract(month from date_id) < 7 then extract(quarter from date_id) + 2
            else extract(quarter from date_id) - 2
        end as fin_quarter,
        case
            when date_id < (date_trunc('year', date_id) + interval 6 month)::date
                then extract(week from (date_id - interval 6 month))::integer
            else extract(week from (date_id + interval 6 month))::integer
        end as fin_week,
    from calendar

)

select
    *,
    concat('p', fin_period) as fin_period_name,
    concat('FQ', fin_quarter) as fin_quarter_name,
    concat('wk', fin_week) as fin_week_name,
from dates_fin
{% endmacro %}
