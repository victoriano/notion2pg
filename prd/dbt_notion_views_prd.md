# Product Requirements Document: DBT Notion Views

## Executive Summary

This PRD outlines the implementation of DBT (Data Build Tool) Core to create materialized tables from raw Notion data stored in PostgreSQL. The solution will transform complex JSON structures from Notion databases into human-readable tables with proper column types and concatenated page content.

## Goal

Transform raw Notion data synced via dlt into clean, materialized PostgreSQL tables where:
- Each Notion database becomes a separate table named `<database_name>_view`
- Each row represents a Notion page/record
- Each column represents a Notion property with human-readable values
- Page content blocks are concatenated into a single text column
- Archived pages are excluded by default

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Data Flow                                │
├─────────────────────────────────────────────────────────────┤
│  Notion API → dlt → Raw PostgreSQL Tables → DBT → Clean    │
│                     (notion_sync schema)      Materialized   │
│                                               Tables         │
└─────────────────────────────────────────────────────────────┘

DBT Layer Structure:
├─ Staging:      Parse raw JSON, extract base fields
├─ Intermediate: Transform property types, fetch page content
└─ Marts:        Final user-friendly tables
```

## Current dlt Table Structure

Based on database inspection, dlt creates the following structure:

### Main Tables
- Named `notion_<database_id_hash>` (e.g., `notion_74f924b4672b4c0ead16511cdfe69396`)
- Properties are already flattened into columns with double underscore notation
- Base columns include: `id`, `created_time`, `last_edited_time`, `archived`, `in_trash`
- Property columns follow pattern: `properties__<property_name>__<attribute>`

### Relation Tables
- Named `notion_<hash>__<property_name>__relation`
- Contains: `id`, `_dlt_root_id` (links to main table), `_dlt_parent_id`, `_dlt_list_idx`
- Stores only the IDs of related records

### Multi-Select Tables
- Named `notion_<hash>__<property_name>__multi_select`
- Contains: `id`, `name`, `color`, `_dlt_root_id` (links to main table)
- Stores the actual values for multi-select options

## Technical Requirements

### 1. Environment & Dependencies
- **DBT Core** (latest stable version)
- **Python 3.11+** for custom DBT macros
- **PostgreSQL 16** (already in stack)
- Python packages:
  - `dbt-postgres`
  - `requests` (for Notion API calls)
  - `beautifulsoup4` (for HTML/text processing)
  - `markdownify` (for markdown conversion)

### 2. DBT Project Structure
```
notion2pg/
├─ dbt_project/
│  ├─ dbt_project.yml
│  ├─ profiles.yml (template)
│  ├─ models/
│  │  ├─ staging/
│  │  │  ├─ _staging.yml
│  │  │  └─ stg_notion__*.sql
│  │  ├─ intermediate/
│  │  │  ├─ _intermediate.yml
│  │  │  └─ int_notion__*.sql
│  │  └─ marts/
│  │     ├─ _marts.yml
│  │     └─ <database_name>_view.sql
│  ├─ macros/
│  │  ├─ parse_notion_properties.sql
│  │  └─ python/
│  │     └─ notion_transformations.py
│  └─ scripts/
│     └─ fetch_page_content.py
```

### 3. Data Transformation Requirements

#### 3.1 Property Type Handling
Since dlt already flattens properties, our transformations will focus on:

**Simple Properties** (already in main table):
- **Text/Title**: Stored in `properties__<name>__title` columns - needs concatenation of rich_text array
- **Number**: Stored in `properties__<name>__number` - direct value
- **Checkbox**: Stored in `properties__<name>__checkbox` - boolean value
- **URL/Email/Phone**: Stored in `properties__<name>__<type>` - direct string
- **Date**: Stored in `properties__<name>__date__start` and `__end` - needs formatting
- **Created/Last edited time**: Already in base columns
- **Select**: Stored with `properties__<name>__select__name` - direct value

**Complex Properties** (in separate tables):
- **Multi-select**: Join with multi_select tables to get names
- **People**: Join with people tables to get names/emails
- **Relation**: Join with relation tables, then lookup related page titles
- **Files**: Join with files tables to get URLs
- **Rollup**: Stored in main table with `__rollup__number` or `__rollup__array`
- **Formula**: Stored in main table with result type

#### 3.2 Page Content Handling
- Page content blocks are NOT currently fetched by dlt
- Need to fetch child blocks for each page via Notion API
- Convert blocks to simple text format initially
- Preserve links to external images
- Concatenate all blocks into single `content` column
- Store in intermediate table for joining

#### 3.3 Data Filtering
- Exclude archived pages (`archived = true`)
- Exclude trashed pages (`in_trash = true`)
- Include only pages from specified database IDs

### 4. Database ID Mapping
Since dlt creates tables with hashed names, we need:
- Configuration mapping database IDs to friendly names
- Discovery mechanism to find all notion tables in the schema
- Dynamic model generation based on available tables

### 4. Integration with Dagster

The DBT transformation should run automatically after each successful Notion sync:

```python
@asset(name="dbt_transform_notion", deps=["notion_sync"])
def dbt_transform_notion_asset(context):
    # Run DBT models
    # Log transformation results
    pass
```

### 5. Performance Considerations
- Use incremental models where possible
- Batch API calls for page content fetching
- Implement caching for unchanged pages
- Target: Process 10K records in < 5 minutes

## Implementation Tasks

### Phase 1: DBT Setup & Basic Structure (Tasks 1-5)

#### Task 1: Initialize DBT Project
**Goal**: Set up DBT project structure with PostgreSQL connection
**Verifiable**: 
- `dbt debug` runs successfully
- Connection to PostgreSQL confirmed
- Project structure created

#### Task 2: Create Database Discovery
**Goal**: Create mechanism to discover and map dlt tables
**Subtasks**:
- Query information_schema to find all notion_* tables
- Create mapping configuration for database IDs to friendly names
- Generate list of available databases dynamically
**Verifiable**: 
- Script can list all Notion tables in the database
- Mapping configuration file created

#### Task 3: Create Staging Models
**Goal**: Create staging models that standardize the dlt structure
**Subtasks**:
- Create base staging model for main tables
- Handle different property column patterns
- Filter out archived and trashed pages
- Create staging models for relation/multi-select tables
**Verifiable**: 
- `dbt run --models staging` executes successfully
- Staging tables contain cleaned data

#### Task 4: Implement Property Type Macros
**Goal**: Create SQL/Jinja macros for transforming each property type
**Subtasks**:
- Title/Rich text concatenation macro
- Date formatting macro
- Multi-select aggregation macro (join and concatenate)
- Relation lookup macro (join and fetch titles)
- People aggregation macro
- Files URL extraction macro
**Verifiable**: 
- Each macro can be tested independently
- Properties correctly transformed to human-readable format

### Phase 2: Advanced Transformations (Tasks 5-8)

#### Task 5: Create Page Content Fetcher
**Goal**: Fetch and process page content blocks
**Subtasks**:
- Create Python script to fetch page blocks via Notion API
- Implement rate limiting and error handling
- Convert blocks to simple text format
- Create DBT Python model or external script to populate content table
**Verifiable**: 
- Script successfully fetches content for sample pages
- Content stored in intermediate table

#### Task 6: Build Intermediate Models
**Goal**: Combine staged data with transformed properties
**Subtasks**:
- Join main tables with related multi-select/relation tables
- Apply property transformation macros
- Add page content from content table
- Create one intermediate model per database
**Verifiable**: 
- Intermediate models contain all transformed columns
- Joins are performant

#### Task 7: Implement Dynamic Model Generation
**Goal**: Generate DBT models dynamically based on available databases
**Subtasks**:
- Create Jinja template for model generation
- Read database mapping configuration
- Generate one model file per database
- Handle schema changes gracefully
**Verifiable**: 
- New databases automatically get models
- Models update when schema changes

### Phase 3: Final Tables & Integration (Tasks 8-10)

#### Task 8: Create Mart Models
**Goal**: Build final user-friendly tables
**Subtasks**:
- Create `<database_name>_view` models
- Ensure column naming is clean and consistent
- Set appropriate materializations (table)
- Add indexes for common queries
**Verifiable**: 
- Final tables exist in PostgreSQL
- Column names are human-readable
- Query performance is acceptable

#### Task 9: Integrate with Dagster Pipeline
**Goal**: Add DBT as downstream asset in Dagster
**Subtasks**:
- Create DBT asset in Dagster
- Configure dependency on notion_sync
- Add error handling and logging
- Update docker setup if needed
**Verifiable**: 
- DBT runs automatically after notion_sync
- Logs show successful transformation
- Dagster UI shows asset dependency

#### Task 10: Create Configuration Management
**Goal**: Make database names and schemas configurable
**Subtasks**:
- Add DBT variables for database mapping
- Create configuration file for database names
- Implement dynamic model generation
**Verifiable**: 
- New databases can be added via configuration
- No code changes needed for new databases

#### Task 11: Add Monitoring and Alerting
**Goal**: Track DBT run performance and failures
**Subtasks**:
- Add run statistics logging
- Create simple health checks
- Configure Dagster alerts for failures
**Verifiable**: 
- Run times are logged
- Failures trigger notifications
- Performance metrics available

## Success Criteria

1. **Functionality**
   - All Notion databases have corresponding `_view` tables
   - All property types correctly transformed
   - Page content available as text column
   - Archived pages excluded

2. **Performance**
   - Full transformation completes in < 5 minutes for 10K records
   - Incremental updates complete in < 1 minute

3. **Reliability**
   - Handles API rate limits gracefully
   - Recovers from transient failures
   - Maintains data consistency

4. **Maintainability**
   - New databases easily added via configuration
   - Property type handlers are modular
   - Clear separation of concerns in DBT layers

## Future Enhancements

1. **Rich Content Format**: Convert page content to Markdown/HTML
2. **Incremental Updates**: Only process changed pages
3. **Data Quality Tests**: Add DBT tests for data validation
4. **Documentation**: Generate DBT docs site
5. **Advanced Transformations**: 
   - Calculated fields
   - Cross-database joins
   - Historical tracking

## Configuration Example

```yaml
# dbt_project.yml
vars:
  notion_databases:
    - database_id: "74f924b4672b4c0ead16511cdfe69396"
      table_name: "notion_74f924b4672b4c0ead16511cdfe69396"
      friendly_name: "categories"
    - database_id: "8931b2899f7848d3bcd13e9b05aae69b"
      table_name: "notion_8931b2899f7848d3bcd13e9b05aae69b"
      friendly_name: "books"
  notion_api_token: "{{ env_var('NOTION_TOKEN') }}"
```

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|---------|------------|
| Notion API rate limits | Delayed transformations | Implement exponential backoff, batch requests |
| Schema changes in Notion | Broken transformations | Dynamic schema detection, graceful degradation |
| Large page content | Memory issues | Stream processing, content size limits |
| Complex property types | Incomplete data | Fallback to JSON representation |

## Dependencies

- Existing notion_sync Dagster asset must be functioning
- PostgreSQL must have sufficient storage for materialized tables
- Notion API token must have read access to page content
- DBT user must have CREATE TABLE permissions

---

Generated for Victoriano · November 2024 