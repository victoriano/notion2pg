{{
  config(
    materialized='table',
    schema='marts',
    alias='categories_view_complete'
  )
}}

-- Complete categories mart view with proper joins to get actual values
-- This shows how to properly extract data from dlt's normalized structure

with categories_base as (
  -- Get base category data from the universal staging
  select 
    *,
    -- Extract _dlt_id from raw_properties for joining
    raw_properties->>'_dlt_id' as dlt_id
  from {{ ref('stg_notion_universal') }}
  where database_name = 'categories'
),

category_titles as (
  -- Join with the title table to get actual category names
  select 
    _dlt_parent_id,
    string_agg(plain_text, ' ' order by _dlt_list_idx) as title
  from {{ source('notion_sync', 'notion_74f924b4672b4c0ead1651bwuwxw_properties__category__title') }}
  group by _dlt_parent_id
),

category_descriptions as (
  -- Get descriptions from rich text table
  select 
    _dlt_parent_id,
    string_agg(plain_text, ' ' order by _dlt_list_idx) as description
  from {{ source('notion_sync', 'notion_74f924b4672b4c0ead1651fotcbwties__description__rich_text') }}
  group by _dlt_parent_id
),

parent_categories as (
  -- Get parent category relations
  select 
    _dlt_parent_id,
    string_agg(id, ', ' order by _dlt_list_idx) as parent_category_ids
  from {{ source('notion_sync', 'notion_74f924b4672b4c0ead16511rjfvas__parent_category__relation') }}
  group by _dlt_parent_id
),

subcategories as (
  -- Get subcategory relations
  select 
    _dlt_parent_id,
    string_agg(id, ', ' order by _dlt_list_idx) as subcategory_ids,
    count(*) as subcategory_count
  from {{ source('notion_sync', 'notion_74f924b4672b4c0ead1651lfshcqies__subcategories__relation') }}
  group by _dlt_parent_id
),

info_required as (
  -- Get information required multi-select values
  select 
    _dlt_root_id,
    string_agg(name, ', ' order by _dlt_list_idx) as information_required
  from {{ source('notion_sync', 'notion_74f924b4672b4c0ead1651gwwcwgation_required__multi_select') }}
  group by _dlt_root_id
)

select 
  -- Core fields
  cb.page_id,
  cb.created_time,
  cb.last_edited_time,
  cb.created_by,
  cb.last_edited_by,
  
  -- Title from joined table
  coalesce(ct.title, 'Untitled') as name,
  
  -- Description from joined table
  coalesce(cd.description, '') as description,
  
  -- Parent category
  pc.parent_category_ids,
  
  -- Subcategories
  coalesce(sc.subcategory_ids, '') as subcategory_ids,
  coalesce(sc.subcategory_count, 0) as subcategory_count,
  
  -- Information required
  coalesce(ir.information_required, '') as information_required,
  
  -- Rollup values from raw JSON
  (cb.raw_properties->>'properties__total_number_of_facts__rollup__number')::int as total_facts_count,
  
  -- Other properties from raw JSON
  cb.raw_properties->>'properties___books__id' as books_relation_id,
  cb.raw_properties->>'properties___facts__id' as facts_relation_id,
  cb.raw_properties->>'properties___articles__id' as articles_relation_id,
  cb.raw_properties->>'properties___videos__id' as videos_relation_id,
  cb.raw_properties->>'properties___datasets__id' as datasets_relation_id,
  cb.raw_properties->>'properties___products__id' as products_relation_id,
  
  -- Keep raw properties for reference
  cb.raw_properties

from categories_base cb
left join category_titles ct on cb.dlt_id = ct._dlt_parent_id
left join category_descriptions cd on cb.dlt_id = cd._dlt_parent_id
left join parent_categories pc on cb.dlt_id = pc._dlt_parent_id
left join subcategories sc on cb.dlt_id = sc._dlt_parent_id
left join info_required ir on cb.dlt_id = ir._dlt_root_id 