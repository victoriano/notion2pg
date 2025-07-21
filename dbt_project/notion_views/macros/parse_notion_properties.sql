{% macro get_multi_select_values(table_name, root_id_column='_dlt_root_id', property_name='') %}
  {# Macro to get comma-separated multi-select values #}
  (
    select string_agg(name, ', ' order by _dlt_list_idx) 
    from {{ source('notion_sync', table_name) }}
    where {{ root_id_column }} = {{ property_name }}
  )
{% endmacro %}

{% macro get_relation_titles(table_name, root_id_column='_dlt_root_id', property_name='', target_table='') %}
  {# Macro to get comma-separated titles from related records #}
  {# This is a placeholder - in reality we'd need to join with the target table to get titles #}
  (
    select string_agg(id, ', ' order by _dlt_list_idx) 
    from {{ source('notion_sync', table_name) }}
    where {{ root_id_column }} = {{ property_name }}
  )
{% endmacro %}

{% macro format_notion_date(date_start, date_end=none) %}
  {# Format Notion date properties #}
  case 
    when {{ date_start }} is null then null
    when {{ date_end }} is null then to_char({{ date_start }}::timestamp, 'YYYY-MM-DD')
    else to_char({{ date_start }}::timestamp, 'YYYY-MM-DD') || ' to ' || to_char({{ date_end }}::timestamp, 'YYYY-MM-DD')
  end
{% endmacro %}

{% macro clean_property_name(property_name) %}
  {# Clean up property names for human readability #}
  {{ property_name | replace('_', ' ') | title }}
{% endmacro %}

{% macro get_rollup_value(rollup_type, rollup_number, rollup_array=none) %}
  {# Get the appropriate rollup value based on type #}
  case 
    when '{{ rollup_type }}' = 'number' then {{ rollup_number }}::text
    when '{{ rollup_type }}' = 'array' and {{ rollup_array }} is not null then {{ rollup_array }}::text
    else 'N/A'
  end
{% endmacro %}
