{# Macro to generate staging models for all configured Notion databases #}

{% macro generate_all_staging_models() %}
  {% set databases = var('notion_databases') %}
  
  {% for db in databases %}
    {% set model_sql %}
-- Auto-generated staging model for {{ db.friendly_name }}
{{ config(
    materialized='view',
    schema='staging',
    alias='stg_notion__' ~ db.friendly_name
) }}

with source_data as (
    select * from {{ source('notion_sync', db.table_name) }}
),

base_columns as (
    select 
        -- Standard Notion fields
        id,
        created_time,
        last_edited_time,
        coalesce(created_by__id, '') as created_by_id,
        coalesce(last_edited_by__id, '') as last_edited_by_id,
        coalesce(archived, false) as archived,
        coalesce(in_trash, false) as in_trash,
        coalesce(parent__database_id, '') as database_id,
        
        -- Add database metadata
        '{{ db.friendly_name }}' as _database_name,
        '{{ db.database_id }}' as _notion_database_id,
        
        -- Include all other columns as-is (they'll be transformed in intermediate layer)
        *
    from source_data
)

select * from base_columns
where 
    archived = false
    and in_trash = false
    {% endset %}
    
    {# Write the model to a file #}
    {% do log("Generated staging model for " ~ db.friendly_name, info=true) %}
    
  {% endfor %}
{% endmacro %}


{# Macro to get all property columns for a specific table #}
{% macro get_property_columns(table_name) %}
  {% set query %}
    select 
        column_name,
        case 
            when column_name like '%__id' then 'id'
            when column_name like '%__type' then 'type'
            when column_name like '%__name' then 'name'
            when column_name like '%__title' then 'title'
            when column_name like '%__number' then 'number'
            when column_name like '%__checkbox' then 'checkbox'
            when column_name like '%__date__start' then 'date_start'
            when column_name like '%__date__end' then 'date_end'
            when column_name like '%__url' then 'url'
            when column_name like '%__email' then 'email'
            when column_name like '%__phone_number' then 'phone'
            else 'complex'
        end as property_type
    from information_schema.columns
    where table_schema = 'notion_sync'
    and table_name = '{{ table_name }}'
    and column_name like 'properties__%'
    order by column_name
  {% endset %}
  
  {% set results = run_query(query) %}
  {% if execute %}
    {% set columns = results.rows %}
    {{ return(columns) }}
  {% else %}
    {{ return([]) }}
  {% endif %}
{% endmacro %} 