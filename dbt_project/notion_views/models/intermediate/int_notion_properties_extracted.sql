{{
  config(
    materialized='table',
    schema='intermediate'
  )
}}

{#- 
  Intermediate model that extracts common properties from the universal staging model.
  This dynamically handles different property types across all databases.
#}

with staged_data as (
  select * from {{ ref('stg_notion_universal') }}
),

properties_extracted as (
  select 
    -- Core fields
    page_id,
    created_time,
    last_edited_time,
    created_by,
    last_edited_by,
    database_name,
    database_id,
    
    -- Extract common property patterns dynamically
    -- Title/Name (most databases have one)
    coalesce(
      raw_properties->>'properties__name__title',
      raw_properties->>'properties__title__title',
      raw_properties->>'properties__Name__title',
      raw_properties->>'properties__Title__title'
    ) as title,
    
    -- Status (common in task/project databases)
    coalesce(
      raw_properties->>'properties__status__select__name',
      raw_properties->>'properties__Status__select__name',
      raw_properties->>'properties__state__select__name'
    ) as status,
    
    -- Categories/Tags (common relationship)
    coalesce(
      raw_properties->>'properties__category__id',
      raw_properties->>'properties__categories__id',
      raw_properties->>'properties__tags__id'
    ) as category_id,
    
    -- Dates (common in most databases)
    coalesce(
      raw_properties->>'properties__date__date__start',
      raw_properties->>'properties__due_date__date__start',
      raw_properties->>'properties__deadline__date__start'
    )::timestamp as due_date,
    
    -- Description/Content (common text field)
    coalesce(
      raw_properties->>'properties__description__rich_text',
      raw_properties->>'properties__content__rich_text',
      raw_properties->>'properties__notes__rich_text'
    ) as description,
    
    -- Numbers (priority, order, count, etc.)
    coalesce(
      (raw_properties->>'properties__priority__number')::numeric,
      (raw_properties->>'properties__order__number')::numeric,
      (raw_properties->>'properties__count__number')::numeric
    ) as numeric_value,
    
    -- Checkbox/Boolean fields
    coalesce(
      (raw_properties->>'properties__done__checkbox')::boolean,
      (raw_properties->>'properties__completed__checkbox')::boolean,
      (raw_properties->>'properties__is_active__checkbox')::boolean,
      false
    ) as is_completed,
    
    -- Keep raw properties for custom extractions
    raw_properties
    
  from staged_data
)

select * from properties_extracted 