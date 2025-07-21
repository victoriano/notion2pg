{{ config(materialized='view') }}

with source_data as (
    select * from {{ source('notion_sync', 'notion_74f924b4672b4c0ead16511cdfe69396') }}
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
        
        -- Property fields (flatten the double underscore structure)
        properties__subcategories__id as subcategories_property_id,
        properties__subcategories__type as subcategories_property_type,
        properties__tweets__id as tweets_property_id,
        properties__tweets__type as tweets_property_type,
        properties__total_number_of_facts__id as total_facts_property_id,
        properties__total_number_of_facts__type as total_facts_property_type,
        properties__total_number_of_facts__rollup__function as total_facts_rollup_function,
        properties__total_number_of_facts__rollup__number as total_facts_rollup_value,
        properties__total_number_of_facts__rollup__type as total_facts_rollup_type
        
    from source_data
)

select * from cleaned
where 
    -- Filter out archived and trashed pages
    (archived = false or archived is null)
    and (in_trash = false or in_trash is null)
