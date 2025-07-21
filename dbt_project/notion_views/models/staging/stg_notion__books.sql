{{ config(materialized='view') }}

with source_data as (
    select * from {{ source('notion_sync', 'notion_8931b2899f7848d3bcd13e9b05aae69b') }}
),

cleaned as (
    select 
        -- Base fields
        id,
        created_time,
        last_edited_time,
        created_by__id as created_by_id,
        last_edited_by__id as last_edited_by_id,
        archived,
        in_trash,
        parent__database_id as database_id,
        
        -- Property fields
        properties__img__id as img_property_id,
        properties__img__type as img_property_type,
        properties__status__id as status_property_id,
        properties__status__type as status_property_type,
        properties__format__id as format_property_id,
        properties__format__type as format_property_type,
        properties__author__id as author_property_id,
        properties__author__type as author_property_type,
        properties__category__id as category_property_id,
        properties__category__type as category_property_type
        
    from source_data
)

select * from cleaned
where 
    -- Filter out archived and trashed pages
    (archived = false or archived is null)
    and (in_trash = false or in_trash is null)
