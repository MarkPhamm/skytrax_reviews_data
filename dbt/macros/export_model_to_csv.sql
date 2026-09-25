{% macro export_model_to_csv(output_subdir) %}
{#-
    Post-hook that writes the model's table out as a single CSV under
    $SKYTRAX_EXPORT_ROOT/<output_subdir>/<relation name>.csv.

    The relation name is the model's alias, so files are named dim_customer.csv,
    fct_airline_review.csv, etc. even though the dbt model names carry a mart
    prefix to stay globally unique.

    DuckDB's COPY will not create missing directories - build.sh creates them
    before invoking dbt.
-#}
{%- set target_dir = env_var('SKYTRAX_EXPORT_ROOT', '../data') ~ '/' ~ output_subdir -%}
{%- set target_path = target_dir ~ '/' ~ this.identifier ~ '.csv' -%}
copy (select * from {{ this }}) to '{{ target_path }}' (format csv, header true, delimiter ',')
{% endmacro %}
