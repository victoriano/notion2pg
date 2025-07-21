{{
  config(
    materialized='table',
    schema='marts',
    alias='books_view_complete'
  )
}}

-- Complete books mart view with proper joins to get actual values
-- This shows how to properly extract data from dlt's normalized structure

with books_base as (
  -- Get base book data from the universal staging
  select 
    *,
    -- Extract _dlt_id from raw_properties for joining
    raw_properties->>'_dlt_id' as dlt_id
  from {{ ref('stg_notion_universal') }}
  where database_name = 'books'
),

book_titles as (
  -- Join with the title table to get actual book names
  select 
    _dlt_parent_id,
    string_agg(plain_text, ' ' order by _dlt_list_idx) as title
  from {{ source('notion_sync', 'notion_8931b2899f7848d3bcd13eczeseg69b__properties__name__title') }}
  group by _dlt_parent_id
),

book_authors as (
  -- Get author names from multi-select table
  select 
    _dlt_root_id,
    string_agg(name, ', ' order by _dlt_list_idx) as author_names
  from {{ source('notion_sync', 'notion_8931b2899f7848d3bcd13ekigqsgerties__author__multi_select') }}
  group by _dlt_root_id
),

book_status as (
  -- Get status values from multi-select table
  select 
    _dlt_root_id,
    string_agg(name, ', ' order by _dlt_list_idx) as status_values
  from {{ source('notion_sync', 'notion_8931b2899f7848d3bcd13exot5zqerties__status__multi_select') }}
  group by _dlt_root_id
),

book_format as (
  -- Get format values from multi-select table
  select 
    _dlt_root_id,
    string_agg(name, ', ' order by _dlt_list_idx) as format_values
  from {{ source('notion_sync', 'notion_8931b2899f7848d3bcd13etpdbvqerties__format__multi_select') }}
  group by _dlt_root_id
)

select 
  -- Core fields
  b.page_id,
  b.created_time,
  b.last_edited_time,
  b.created_by,
  b.last_edited_by,
  
  -- Title from joined table
  coalesce(bt.title, 'Untitled') as title,
  
  -- Multi-select values from joined tables
  coalesce(ba.author_names, '') as authors,
  coalesce(bs.status_values, '') as status,
  coalesce(bf.format_values, '') as format,
  
  -- Other properties from raw JSON
  b.raw_properties->>'properties__category__id' as category_id,
  b.raw_properties->>'properties__img__id' as image_id,
  b.raw_properties->>'properties__subtitle__rich_text' as subtitle,
  b.raw_properties->>'properties__why_read_it__rich_text' as why_read_it,
  b.raw_properties->>'properties__book_in_amazon__url' as amazon_url,
  
  -- Keep raw properties for reference
  b.raw_properties

from books_base b
left join book_titles bt on b.dlt_id = bt._dlt_parent_id
left join book_authors ba on b.dlt_id = ba._dlt_root_id
left join book_status bs on b.dlt_id = bs._dlt_root_id
left join book_format bf on b.dlt_id = bf._dlt_root_id 