{{
  config(
    materialized='view',
    schema='staging'
  )
}}

{#- 
  Universal staging model for ALL Notion databases.
  This single model dynamically handles all configured databases.
  
  Benefits:
  - No need to create new models when adding databases
  - Consistent structure across all databases
  - Easy to maintain and debug
  - Can query all databases at once or filter by _database_name
#}

{% set databases = var('notion_databases') %}

{% for db in databases %}
  {% if not loop.first %}
  union all
  {% endif %}
  
  select 
    -- Standard Notion fields (present in all databases)
    id,
    created_time,
    last_edited_time,
    coalesce(archived, false) as archived,
    coalesce(in_trash, false) as in_trash,
    
    -- System fields (safely handle if they don't exist)
    cast(nullif(created_by__id, '') as varchar) as created_by_id,
    cast(nullif(last_edited_by__id, '') as varchar) as last_edited_by_id,
    cast(nullif(parent__database_id, '') as varchar) as parent_database_id,
    
    -- Database metadata (for filtering and identification)
    '{{ db.friendly_name }}' as _database_name,
    '{{ db.database_id }}' as _notion_database_id,
    '{{ db.table_name }}' as _source_table,
    
    -- Properties as JSON (preserving all properties without knowing structure)
    -- This approach keeps all property columns but in a structured way
    to_jsonb(
      (select 
        jsonb_object_agg(
          replace(replace(column_name, 'properties__', ''), '__', '_'),
          case 
            when data_type in ('bigint', 'integer', 'numeric') then to_jsonb(t.column_value::numeric)
            when data_type = 'boolean' then to_jsonb(t.column_value::boolean)
            when data_type = 'timestamp with time zone' then to_jsonb(t.column_value::text)
            else to_jsonb(t.column_value)
          end
        )
      from (
        select 
          column_name,
          data_type,
          case column_name
            {% for col in adapter.get_columns_in_relation(source('notion_sync', db.table_name)) %}
            {% if col.name.startswith('properties__') %}
            when '{{ col.name }}' then {{ col.name }}::text
            {% endif %}
            {% endfor %}
          end as column_value
        from information_schema.columns
        where table_schema = 'notion_sync'
          and table_name = '{{ db.table_name }}'
          and column_name like 'properties__%'
      ) t
      where t.column_value is not null)
    ) as properties_json
    
  from {{ source('notion_sync', db.table_name) }}
  where coalesce(archived, false) = false
    and coalesce(in_trash, false) = false

{% endfor %} 