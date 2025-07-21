{{
  config(
    materialized='table',
    schema='marts',
    alias='facts_view_complete'
  )
}}

-- Complete facts mart view with proper joins to get actual values
-- This shows how to properly extract data from dlt's normalized structure

with facts_base as (
  -- Get base fact data from the universal staging
  select 
    *,
    -- Extract _dlt_id from raw_properties for joining
    raw_properties->>'_dlt_id' as dlt_id
  from {{ ref('stg_notion_universal') }}
  where database_name = 'facts'
),

fact_titles as (
  -- Join with the title table to get actual fact text
  select 
    _dlt_parent_id,
    string_agg(plain_text, ' ' order by _dlt_list_idx) as fact_text
  from {{ source('notion_sync', 'notion_b981dec447fb4060877505kdsprg45c__properties__name__title') }}
  group by _dlt_parent_id
),

why_read_it as (
  -- Get why read it text
  select 
    _dlt_parent_id,
    string_agg(plain_text, ' ' order by _dlt_list_idx) as why_read_it
  from {{ source('notion_sync', 'notion_b981dec447fb4060877505rtuspaties__why_read_it__rich_text') }}
  group by _dlt_parent_id
),

fact_categories as (
  -- Get category relations
  select 
    _dlt_parent_id,
    string_agg(id, ', ' order by _dlt_list_idx) as category_ids,
    count(*) as category_count
  from {{ source('notion_sync', 'notion_b981dec447fb4060877505vxkhqwoperties__category__relation') }}
  group by _dlt_parent_id
),

-- Get all categories for name lookup
categories as (
  select 
    page_id as category_id,
    name as category_name
  from {{ ref('categories_view_complete') }}
),

-- Join fact categories with category names
fact_category_names as (
  select 
    fc._dlt_parent_id,
    string_agg(coalesce(c.category_name, fcr.id), ', ' order by fcr._dlt_list_idx) as category_names
  from {{ source('notion_sync', 'notion_b981dec447fb4060877505vxkhqwoperties__category__relation') }} fcr
  join fact_categories fc on fc._dlt_parent_id = fcr._dlt_parent_id
  left join categories c on c.category_id = fcr.id
  group by fc._dlt_parent_id
)

select 
  -- Core fields
  fb.page_id,
  fb.created_time,
  fb.last_edited_time,
  fb.created_by,
  fb.last_edited_by,
  
  -- Fact text from joined table
  coalesce(ft.fact_text, 'Untitled') as fact_text,
  
  -- Why read it from joined table
  coalesce(wri.why_read_it, '') as why_read_it,
  
  -- Categories with both IDs and names
  coalesce(fc.category_ids, '') as category_ids,
  coalesce(fcn.category_names, '') as category_names,
  coalesce(fc.category_count, 0) as category_count,
  
  -- Other properties from raw JSON
  fb.raw_properties->>'properties__img__id' as image_id,
  fb.raw_properties->>'properties__created_time__created_time' as notion_created_time,
  fb.raw_properties->>'properties__source__rich_text' as source,
  (fb.raw_properties->>'properties__verified__checkbox')::boolean as is_verified,
  fb.raw_properties->>'properties__tags__multi_select' as tags,
  
  -- URLs and links
  fb.raw_properties->>'properties__url__url' as fact_url,
  
  -- Keep raw properties for reference
  fb.raw_properties

from facts_base fb
left join fact_titles ft on fb.dlt_id = ft._dlt_parent_id
left join why_read_it wri on fb.dlt_id = wri._dlt_parent_id
left join fact_categories fc on fb.dlt_id = fc._dlt_parent_id
left join fact_category_names fcn on fb.dlt_id = fcn._dlt_parent_id 