{{
  config(
    materialized='table',
    schema='marts'
  )
}}

-- Books mart view - extracts and transforms book-specific properties
-- Built on top of the generic staging model

with staged_data as (
  select * 
  from {{ ref('stg_notion_universal') }}
  where database_name = 'books'
),

properties_extracted as (
  select 
    -- Core fields
    page_id,
    created_time,
    last_edited_time,
    created_by,
    last_edited_by,
    
    -- Extract book-specific properties from JSON
    -- Books use 'name' property for title
    raw_properties->>'properties__name__title' as title,
    
    -- Author (multi-select)
    raw_properties->>'properties__author__id' as author_id,
    
    -- Status (multi-select)
    raw_properties->>'properties__status__id' as status_id,
    
    -- Format (multi-select)
    raw_properties->>'properties__format__id' as format_id,
    
    -- Category relation
    raw_properties->>'properties__category__id' as category_id,
    
    -- Image files
    raw_properties->>'properties__img__id' as image_id,
    
    -- Rich text fields
    raw_properties->>'properties__subtitle__rich_text' as subtitle,
    raw_properties->>'properties__why_read_it__rich_text' as why_read_it,
    
    -- Keep raw properties for any custom needs
    raw_properties
    
  from staged_data
),

-- Join with multi-select tables to get actual values
-- (This is a simplified version - in production you'd join the actual multi-select tables)
final_output as (
  select 
    *,
    -- Placeholder for multi-select values - these would come from joins
    'TODO: Join with author multi-select table' as author_names,
    'TODO: Join with status multi-select table' as status_values,
    'TODO: Join with format multi-select table' as format_values
  from properties_extracted
)

select * from final_output 