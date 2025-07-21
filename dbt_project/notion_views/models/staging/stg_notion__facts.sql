{{ config(materialized='view') }}

with source_data as (
    select * from {{ source('notion_sync', 'notion_b981dec447fb4060877505e8cc63a45c') }}
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
        
        -- Property fields for facts table
        properties__category__id as category_property_id,
        properties__category__type as category_property_type
        
    from source_data
)

select * from cleaned
where 
    -- Filter out archived and trashed pages
    (archived = false or archived is null)
    and (in_trash = false or in_trash is null)
