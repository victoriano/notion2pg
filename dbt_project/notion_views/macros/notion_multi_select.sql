{% macro get_books_status(page_id) %}
  {# Get status values for books from the multi-select table #}
  (
    select string_agg(name, ', ' order by _dlt_list_idx) 
    from {{ source('notion_sync', 'notion_8931b2899f7848d3exot5zqerties__status__multi_select') }}
    where _dlt_root_id = '{{ page_id }}'
  )
{% endmacro %}

{% macro get_books_format(page_id) %}
  {# Get format values for books from the multi-select table #}
  (
    select string_agg(name, ', ' order by _dlt_list_idx) 
    from {{ source('notion_sync', 'notion_8931b2899f7848d3etpdbvqerties__format__multi_select') }}
    where _dlt_root_id = '{{ page_id }}'
  )
{% endmacro %}

{% macro get_books_author(page_id) %}
  {# Get author values for books from the multi-select table #}
  (
    select string_agg(name, ', ' order by _dlt_list_idx) 
    from {{ source('notion_sync', 'notion_8931b2899f7848d3ekigqsgerties__author__multi_select') }}
    where _dlt_root_id = '{{ page_id }}'
  )
{% endmacro %}

{% macro get_categories_information_required(page_id) %}
  {# Get information required values for categories from the multi-select table #}
  (
    select string_agg(name, ', ' order by _dlt_list_idx) 
    from {{ source('notion_sync', 'notion_74f924b4672b4c0ead1651gwwcwgation_required__multi_select') }}
    where _dlt_root_id = '{{ page_id }}'
  )
{% endmacro %}
