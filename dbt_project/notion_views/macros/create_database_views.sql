{# Macro to create individual views for each database from the universal model #}

{% macro create_database_specific_views() %}
  {% set databases = var('notion_databases') %}
  
  {% for db in databases %}
    create or replace view {{ target.schema }}_marts.{{ db.friendly_name }}_view as
    select 
      page_id,
      created_time,
      last_edited_time,
      created_by,
      last_edited_by,
      title,
      status,
      category_id,
      due_date,
      description,
      numeric_value,
      is_completed,
      
      -- Extract database-specific properties using JSON
      {% if db.friendly_name == 'books' %}
      raw_properties->>'properties__author__id' as author,
      raw_properties->>'properties__isbn__rich_text' as isbn,
      raw_properties->>'properties__format__id' as format,
      {% elif db.friendly_name == 'categories' %}
      raw_properties->>'properties__parent_category__id' as parent_category,
      (raw_properties->>'properties__total_number_of_facts__rollup__number')::int as total_facts,
      {% elif db.friendly_name == 'facts' %}
      raw_properties->>'properties__source__rich_text' as source,
      raw_properties->>'properties__verified__checkbox' as is_verified,
      {% endif %}
      
      -- Always include raw properties for flexibility
      raw_properties
      
    from {{ ref('int_notion_properties_extracted') }}
    where database_name = '{{ db.friendly_name }}';
  {% endfor %}
{% endmacro %}

{# Run this macro as a post-hook on the intermediate model #}
{% macro create_all_database_views() %}
  {% if execute %}
    {% do run_query(create_database_specific_views()) %}
    {{ log("Created database-specific views for all configured databases", info=True) }}
  {% endif %}
{% endmacro %} 