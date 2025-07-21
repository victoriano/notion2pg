{{
  config(
    materialized='table',
    schema='staging'
  )
}}

{#- 
  Simplified universal staging model for ALL Notion databases.
  Uses UNION ALL to combine all databases with a consistent structure.
  
  To add a new database:
  1. Add it to the notion_databases variable in dbt_project.yml
  2. Re-run this model - no code changes needed!
#}

{% set databases = var('notion_databases') %}

with all_databases as (
  {% for db in databases %}
  {% if not loop.first %}
  union all
  {% endif %}
  
  select 
    -- Core fields
    id as page_id,
    created_time,
    last_edited_time,
    coalesce(archived, false) as is_archived,
    coalesce(in_trash, false) as is_trashed,
    
    -- User tracking
    coalesce(created_by__id, 'unknown') as created_by,
    coalesce(last_edited_by__id, 'unknown') as last_edited_by,
    
    -- Database info
    '{{ db.friendly_name }}' as database_name,
    '{{ db.database_id }}' as database_id,
    
    -- Preserve all columns as JSON
    to_json(t.*) as raw_properties
    
  from {{ source('notion_sync', db.table_name) }} as t
  
  {% endfor %}
),

filtered as (
  select *
  from all_databases
  where not is_archived
    and not is_trashed
)

select * from filtered 