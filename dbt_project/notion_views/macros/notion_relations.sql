{% macro get_books_category_relation(page_id) %}
  {# Get category relation for books - returns the related category IDs #}
  (
    select string_agg(id, ', ' order by _dlt_list_idx) 
    from {{ source('notion_sync', 'notion_8931b2899f7848d3exyhgkgoperties__category__relation') }}
    where _dlt_root_id = '{{ page_id }}'
  )
{% endmacro %}

{% macro get_facts_category_relation(page_id) %}
  {# Get category relation for facts - returns the related category IDs #}
  (
    select string_agg(id, ', ' order by _dlt_list_idx) 
    from {{ source('notion_sync', 'notion_b981dec447fb4060877505vxkhqwoperties__category__relation') }}
    where _dlt_root_id = '{{ page_id }}'
  )
{% endmacro %}

{% macro get_categories_subcategories_relation(page_id) %}
  {# Get subcategories relation for categories - returns the related subcategory IDs #}
  (
    select string_agg(id, ', ' order by _dlt_list_idx) 
    from {{ source('notion_sync', 'notion_74f924b4672b4c0ead1651lfshcqies__subcategories__relation') }}
    where _dlt_root_id = '{{ page_id }}'
  )
{% endmacro %}

{% macro get_categories_parent_category_relation(page_id) %}
  {# Get parent category relation for categories - returns the related parent category ID #}
  (
    select string_agg(id, ', ' order by _dlt_list_idx) 
    from {{ source('notion_sync', 'notion_74f924b4672b4c0ead16511rjfvas__parent_category__relation') }}
    where _dlt_root_id = '{{ page_id }}'
  )
{% endmacro %}
