{{
  config(
    materialized='table',
    schema='marts'
  )
}}

-- Facts mart view - extracts and transforms fact-specific properties
-- Built on top of the generic staging model

with staged_data as (
  select * 
  from {{ ref('stg_notion_universal') }}
  where database_name = 'facts'
),

properties_extracted as (
  select 
    -- Core fields
    page_id,
    created_time,
    last_edited_time,
    created_by,
    last_edited_by,
    
    -- Extract fact-specific properties from JSON
    coalesce(
      raw_properties->>'properties__name__title',
      raw_properties->>'properties__title__title',
      raw_properties->>'properties__fact__title'
    ) as fact_text,
    
    -- Category relation
    raw_properties->>'properties__category__id' as category_id,
    
    -- Other fact-specific fields
    raw_properties->>'properties__source__rich_text' as source,
    (raw_properties->>'properties__verified__checkbox')::boolean as is_verified,
    raw_properties->>'properties__tags__multi_select' as tags,
    
    -- Keep raw properties for any custom needs
    raw_properties
    
  from staged_data
)

select * from properties_extracted 