{{
  config(
    materialized='table',
    schema='marts'
  )
}}

-- Categories mart view - extracts and transforms category-specific properties
-- Built on top of the generic staging model

with staged_data as (
  select * 
  from {{ ref('stg_notion_universal') }}
  where database_name = 'categories'
),

properties_extracted as (
  select 
    -- Core fields
    page_id,
    created_time,
    last_edited_time,
    created_by,
    last_edited_by,
    
    -- Extract category-specific properties from JSON
    coalesce(
      raw_properties->>'properties__name__title',
      raw_properties->>'properties__title__title'
    ) as name,
    
    -- Parent category relation
    raw_properties->>'properties__parent_category__id' as parent_category_id,
    
    -- Subcategories relation  
    raw_properties->>'properties__subcategories__id' as subcategories_id,
    
    -- Facts relation
    raw_properties->>'properties___facts__id' as facts_relation_id,
    
    -- Rollup values
    (raw_properties->>'properties__total_number_of_facts__rollup__number')::int as total_facts_count,
    
    -- Other properties
    raw_properties->>'properties__description__rich_text' as description,
    
    -- Keep raw properties for any custom needs
    raw_properties
    
  from staged_data
)

select * from properties_extracted 