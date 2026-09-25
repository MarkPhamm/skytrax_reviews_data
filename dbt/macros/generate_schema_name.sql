{% macro generate_schema_name(custom_schema_name, node) -%}
{#-
    Use custom schema names verbatim instead of dbt's default
    <target_schema>_<custom_schema> concatenation, so each mart lands in a
    clean schema (airlines_reviews, airport_reviews, ...) that mirrors its
    CSV output directory.
-#}
    {%- if custom_schema_name is none -%}
        {{ target.schema | trim }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
