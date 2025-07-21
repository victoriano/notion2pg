#!/usr/bin/env python3
"""
Discover Notion databases from PostgreSQL and generate configuration.
This script queries the information_schema to find all notion_* tables
and generates the configuration needed for DBT models.
"""

import psycopg2
import yaml
import os
import json
from typing import List, Dict, Any

def get_db_connection():
    """Get connection to PostgreSQL database."""
    return psycopg2.connect(
        host=os.getenv('PGHOST', 'localhost'),
        port=os.getenv('PGPORT', '5432'),
        database=os.getenv('PGDATABASE', 'analytics'),
        user=os.getenv('PGUSER', 'postgres'),
        password=os.getenv('PGPASSWORD', 'supersecret')
    )

def discover_notion_tables(conn) -> List[Dict[str, Any]]:
    """Discover all notion_* tables in the notion_sync schema."""
    cursor = conn.cursor()
    
    # Find all main notion tables (not relation/multi-select tables)
    cursor.execute("""
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'notion_sync'
        AND table_name LIKE 'notion_%'
        AND table_name NOT LIKE '%__%'
        AND table_name NOT IN ('_dlt_loads', '_dlt_pipeline_state', '_dlt_version')
        ORDER BY table_name;
    """)
    
    tables = cursor.fetchall()
    discovered_databases = []
    
    for (table_name,) in tables:
        # Extract the hash part from table name (after notion_)
        table_hash = table_name.replace('notion_', '')
        
        # Get basic info about the table
        cursor.execute("""
            SELECT 
                COUNT(*) as row_count,
                COUNT(CASE WHEN archived = false OR archived IS NULL THEN 1 END) as active_rows
            FROM notion_sync.%s;
        """ % table_name)  # Note: In production, use parameterized queries
        
        row_count, active_rows = cursor.fetchone()
        
        # Try to find a title property to guess friendly name
        cursor.execute("""
            SELECT column_name 
            FROM information_schema.columns 
            WHERE table_schema = 'notion_sync'
            AND table_name = %s
            AND column_name LIKE 'properties%%title%%'
            LIMIT 1;
        """, (table_name,))
        
        title_column = cursor.fetchone()
        
        database_info = {
            'database_id': table_hash,
            'table_name': table_name,
            'friendly_name': table_hash[:8],  # Use first 8 chars as default friendly name
            'row_count': row_count,
            'active_rows': active_rows,
            'has_title_property': title_column is not None,
            'title_column': title_column[0] if title_column else None
        }
        
        discovered_databases.append(database_info)
    
    cursor.close()
    return discovered_databases

def discover_related_tables(conn, main_table: str) -> Dict[str, List[str]]:
    """Discover relation and multi-select tables for a main table."""
    cursor = conn.cursor()
    
    # Find related tables (those with the main table hash in their name)
    table_hash = main_table.replace('notion_', '')
    
    cursor.execute("""
        SELECT table_name, 
               CASE 
                   WHEN table_name LIKE '%__relation' THEN 'relation'
                   WHEN table_name LIKE '%__multi_select' THEN 'multi_select'
                   WHEN table_name LIKE '%__files' THEN 'files'
                   WHEN table_name LIKE '%__people' THEN 'people'
                   WHEN table_name LIKE '%__rich_text' THEN 'rich_text'
                   WHEN table_name LIKE '%__title' THEN 'title'
                   ELSE 'other'
               END as table_type
        FROM information_schema.tables 
        WHERE table_schema = 'notion_sync'
        AND table_name LIKE %s
        AND table_name != %s
        ORDER BY table_name;
    """, (f'%{table_hash}%', main_table))
    
    related_tables = cursor.fetchall()
    
    # Group by type
    related_by_type = {}
    for table_name, table_type in related_tables:
        if table_type not in related_by_type:
            related_by_type[table_type] = []
        related_by_type[table_type].append(table_name)
    
    cursor.close()
    return related_by_type

def generate_dbt_sources_config(databases: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Generate DBT sources configuration."""
    
    sources_config = {
        'version': 2,
        'sources': [
            {
                'name': 'notion_sync',
                'description': 'Raw Notion data synced via dlt',
                'schema': 'notion_sync',
                'tables': []
            }
        ]
    }
    
    # Add main tables
    for db in databases:
        table_config = {
            'name': db['table_name'],
            'description': f"Notion database: {db['friendly_name']} ({db['active_rows']} active records)",
            'meta': {
                'database_id': db['database_id'],
                'friendly_name': db['friendly_name'],
                'row_count': db['row_count'],
                'active_rows': db['active_rows']
            }
        }
        sources_config['sources'][0]['tables'].append(table_config)
    
    return sources_config

def main():
    """Main discovery function."""
    print("🔍 Discovering Notion databases...")
    
    try:
        conn = get_db_connection()
        
        # Discover main tables
        databases = discover_notion_tables(conn)
        print(f"Found {len(databases)} Notion databases:")
        
        for db in databases:
            print(f"  • {db['table_name']} ({db['active_rows']} active records)")
            
            # Discover related tables for each main table
            related = discover_related_tables(conn, db['table_name'])
            if related:
                for table_type, tables in related.items():
                    print(f"    - {table_type}: {len(tables)} tables")
        
        # Generate DBT sources configuration
        sources_config = generate_dbt_sources_config(databases)
        
        # Save sources configuration
        os.makedirs('../models/staging', exist_ok=True)
        with open('../models/staging/_sources.yml', 'w') as f:
            yaml.dump(sources_config, f, default_flow_style=False, sort_keys=False)
        
        print(f"\n✅ Generated sources configuration: models/staging/_sources.yml")
        
        # Also save detailed discovery results
        with open('../discovered_databases.json', 'w') as f:
            json.dump(databases, f, indent=2)
        
        print(f"📋 Saved detailed discovery results: discovered_databases.json")
        
        conn.close()
        
    except Exception as e:
        print(f"❌ Error: {e}")
        return 1
    
    return 0

if __name__ == '__main__':
    exit(main()) 