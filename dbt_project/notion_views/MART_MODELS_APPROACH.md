# Mart Models Approach - Best of Both Worlds

This guide explains how we achieve your goal of having **individual materialized tables for each Notion database** while still using **generic models** for processing.

## 🎯 Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Data Flow                            │
├─────────────────────────────────────────────────────────┤
│ Raw Data → Generic Staging → Individual Mart Tables     │
│                                                         │
│ notion_sync.*  →  stg_notion_universal  →  books_view  │
│                                         →  facts_view   │
│                                         →  categories_view
└─────────────────────────────────────────────────────────┘
```

## 📊 Final Result

You get exactly what you want:
- **Separate materialized tables** for each database
- **Named after the database** (e.g., `books_view`, `categories_view`)
- **Optimized columns** specific to each database
- **No custom staging models needed** when adding new databases

## 🚀 Two Approaches for Mart Models

### Approach 1: Custom Mart Models (Recommended for Important Databases)

For databases you query frequently, create custom mart models with specific property extraction:

```sql
-- models/marts/books_view.sql
{{
  config(
    materialized='table',
    schema='marts'
  )
}}

with staged_data as (
  select * 
  from {{ ref('stg_notion_universal') }}
  where database_name = 'books'
),

properties_extracted as (
  select 
    page_id,
    created_time,
    -- Extract book-specific properties
    raw_properties->>'properties__title__title' as title,
    raw_properties->>'properties__author__id' as author_id,
    -- ... more properties
  from staged_data
)

select * from properties_extracted
```

**Benefits**:
- Full control over column names and types
- Can add complex joins and transformations
- Best performance for queries

### Approach 2: Generic Mart Generation (For Simple Databases)

For simpler databases or quick prototyping, use the macro to generate marts:

```sql
-- Run this to create mart views for all databases
dbt run-operation generate_all_mart_views
```

Or create a generic mart model:

```sql
-- models/marts/auto_generated_mart.sql
{{ generate_mart_sql(var('current_database')) }}
```

## 📋 Step-by-Step: Adding a New Database

### If you want a custom mart:

1. **Add to configuration** (`dbt_project.yml`):
   ```yaml
   - database_id: "new_db_id"
     table_name: "notion_new_db_id"
     friendly_name: "projects"
   ```

2. **Run generic staging**:
   ```bash
   dbt run --select stg_notion_universal
   ```

3. **Create custom mart** (`models/marts/projects_view.sql`):
   ```sql
   {{
     config(
       materialized='table',
       schema='marts'
     )
   }}
   
   select 
     page_id,
     raw_properties->>'properties__name__title' as project_name,
     raw_properties->>'properties__status__select__name' as status,
     -- ... your specific properties
   from {{ ref('stg_notion_universal') }}
   where database_name = 'projects'
   ```

4. **Run the mart**:
   ```bash
   dbt run --select projects_view
   ```

### If you want automatic generation:

1. **Add to configuration** (same as above)

2. **Run everything**:
   ```bash
   dbt run --select stg_notion_universal
   dbt run-operation generate_all_mart_views
   ```

## 🔍 Query Examples

Once your marts are created, you can query them directly:

```sql
-- Simple, clean queries on materialized tables
SELECT * FROM marts.books_view WHERE title LIKE '%Python%';

SELECT * FROM marts.categories_view WHERE parent_category_id IS NULL;

SELECT * FROM marts.facts_view WHERE is_verified = true;

-- Join across marts (much easier than with raw data)
SELECT 
  b.title as book_title,
  c.name as category_name
FROM marts.books_view b
JOIN marts.categories_view c ON b.category_id = c.page_id;
```

## 💡 Best Practices

1. **Use custom marts for**:
   - Frequently queried databases
   - Databases with complex properties
   - When you need specific transformations

2. **Use generic marts for**:
   - Simple databases
   - Rarely queried databases
   - Quick prototyping

3. **Always keep `raw_properties`** in your marts for flexibility

## 🎯 Summary

- ✅ **Generic staging model** = No repetitive staging code
- ✅ **Individual mart tables** = Clean, optimized final tables
- ✅ **Database names preserved** = `books_view`, `categories_view`, etc.
- ✅ **Flexible approach** = Custom or generated marts as needed
- ✅ **Easy to maintain** = Add database to config, create mart, done!

This gives you the best of both worlds: efficient generic processing with clean, specific output tables! 