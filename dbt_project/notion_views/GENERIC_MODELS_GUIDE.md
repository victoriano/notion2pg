# Generic DBT Models for Notion Databases

This guide explains how to use generic models that automatically handle any Notion database without creating custom models for each one.

## 🎯 Overview

Instead of creating custom staging models for each Notion database (like `stg_notion__books.sql`, `stg_notion__categories.sql`), you can use generic models that dynamically handle any database structure.

## 📋 Available Approaches

### 1. **Universal SQL Model** (Recommended) ✅
**File**: `models/staging/stg_notion_universal.sql`

The simplest and most maintainable approach. Creates a single table/view containing ALL Notion databases.

**Benefits**:
- Single model handles all databases
- Easy to query across databases
- JSON column preserves all properties
- No code changes when adding databases

**Usage**:
```sql
-- Query all databases
SELECT * FROM staging.stg_notion_universal;

-- Query specific database
SELECT * FROM staging.stg_notion_universal 
WHERE database_name = 'books';

-- Extract specific properties
SELECT 
  page_id,
  database_name,
  raw_properties->>'properties__title__title' as title
FROM staging.stg_notion_universal;
```

### 2. **Python Dynamic Model**
**File**: `models/staging/stg_notion_dynamic.py`

Uses DBT's Python models to dynamically process databases with Pandas.

**Benefits**:
- More flexible data transformations
- Can handle complex logic
- Better for data science workflows

**Usage**:
```bash
# Process all databases
dbt run --select stg_notion_dynamic

# Process specific database
dbt run --select stg_notion_dynamic --vars 'target_database: books'
```

### 3. **Macro-Generated Views**
**File**: `macros/create_database_views.sql`

Creates individual views for each database from the universal model.

**Benefits**:
- Database-specific views with custom columns
- Clean interface for end users
- Can add database-specific logic

## 🚀 Quick Start

### Step 1: Configure Your Databases
Add your Notion databases to `dbt_project.yml`:

```yaml
vars:
  notion_databases:
    - database_id: "abc123..."
      table_name: "notion_abc123..."
      friendly_name: "projects"
    - database_id: "def456..."
      table_name: "notion_def456..."
      friendly_name: "tasks"
```

### Step 2: Run the Universal Model
```bash
dbt run --select stg_notion_universal
```

### Step 3: Query Your Data
```sql
-- All projects
SELECT * FROM staging.stg_notion_universal 
WHERE database_name = 'projects';

-- Extract title from any database
SELECT 
  page_id,
  database_name,
  coalesce(
    raw_properties->>'properties__name__title',
    raw_properties->>'properties__title__title',
    raw_properties->>'properties__Name__title'
  ) as title
FROM staging.stg_notion_universal;
```

## 🔧 Adding a New Database

1. **Get the database info** from your Notion sync:
   ```sql
   SELECT table_name 
   FROM information_schema.tables 
   WHERE table_schema = 'notion_sync' 
   AND table_name LIKE 'notion_%';
   ```

2. **Add to configuration**:
   ```yaml
   - database_id: "new123..."
     table_name: "notion_new123..."
     friendly_name: "my_new_db"
   ```

3. **Re-run the model**:
   ```bash
   dbt run --select stg_notion_universal
   ```

That's it! No code changes needed.

## 🎨 Customization Examples

### Extract Common Properties
Create a view that extracts common properties across all databases:

```sql
CREATE VIEW all_notion_titles AS
SELECT 
  page_id,
  database_name,
  created_time,
  -- Try multiple common title patterns
  coalesce(
    raw_properties->>'properties__name__title',
    raw_properties->>'properties__title__title',
    raw_properties->>'properties__Name__title',
    raw_properties->>'properties__Title__title'
  ) as title
FROM staging.stg_notion_universal;
```

### Database-Specific Views
Use the macro to create custom views:

```sql
{{ create_database_specific_views() }}
```

Or create manually:

```sql
CREATE VIEW marts.projects_view AS
SELECT 
  page_id,
  created_time,
  raw_properties->>'properties__name__title' as project_name,
  raw_properties->>'properties__status__select__name' as status,
  raw_properties->>'properties__due_date__date__start' as due_date
FROM staging.stg_notion_universal
WHERE database_name = 'projects';
```

## 📊 Example Queries

### Find all pages created this week
```sql
SELECT database_name, count(*) as new_pages
FROM staging.stg_notion_universal
WHERE created_time >= current_date - interval '7 days'
GROUP BY database_name;
```

### Get all incomplete tasks
```sql
SELECT 
  page_id,
  raw_properties->>'properties__title__title' as task_name,
  created_time
FROM staging.stg_notion_universal
WHERE database_name = 'tasks'
  AND (raw_properties->>'properties__done__checkbox')::boolean = false;
```

### Cross-database relationships
```sql
-- Find all books in a specific category
SELECT 
  b.page_id,
  b.raw_properties->>'properties__title__title' as book_title,
  c.raw_properties->>'properties__name__title' as category_name
FROM staging.stg_notion_universal b
JOIN staging.stg_notion_universal c 
  ON b.raw_properties->>'properties__category__id' = c.page_id
WHERE b.database_name = 'books'
  AND c.database_name = 'categories';
```

## 🔍 Debugging

### See all available properties for a database
```sql
SELECT 
  jsonb_object_keys(raw_properties) as property_name
FROM staging.stg_notion_universal
WHERE database_name = 'your_database'
LIMIT 1;
```

### Check what databases are included
```sql
SELECT DISTINCT database_name, count(*) as record_count
FROM staging.stg_notion_universal
GROUP BY database_name;
```

## 💡 Best Practices

1. **Use the universal model** for most use cases - it's the simplest
2. **Create views** for specific databases only when needed
3. **Keep raw_properties** in your views for flexibility
4. **Document property mappings** for each database
5. **Use coalesce()** for common patterns across databases

## 🚨 Limitations

- JSON extraction can be slower than direct columns
- Property names must be known (but you can query them dynamically)
- Complex multi-select and relation joins need additional logic

## 🎯 Summary

The generic model approach means:
- ✅ No new SQL files when adding databases
- ✅ Consistent structure across all databases  
- ✅ Easy to maintain and debug
- ✅ Flexible property extraction
- ✅ Single source of truth

Just add your database to the config and run - it just works! 🎉 