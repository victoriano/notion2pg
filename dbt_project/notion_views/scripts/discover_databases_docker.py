#!/usr/bin/env python3
"""
Discover Notion databases from Docker PostgreSQL and generate configuration.
"""

import subprocess
import json
import yaml
import os
from typing import List, Dict, Any

def run_docker_sql(sql: str) -> List[tuple]:
    """Execute SQL in the Docker PostgreSQL container."""
    cmd = [
        'docker', 'exec', '-i', 'notion2pg-postgres_dwh-1',
        'psql', '-U', 'postgres', '-d', 'analytics', '-t', '-c', sql
    ]
    
    result = subprocess.run(cmd, capture_output=True, text=True, cwd='../../..')
    if result.returncode != 0:
        raise Exception(f"SQL execution failed: {result.stderr}")
    
    # Parse the output into rows
    lines = result.stdout.strip().split('\n')
    rows = []
    for line in lines:
        line = line.strip()
        if line and line != '(0 rows)' and not line.startswith('---'):
            # Split by pipe if multiple columns, otherwise single value
            if '|' in line:
                rows.append(tuple(col.strip() for col in line.split('|')))
            else:
                rows.append((line,))
    
    return rows

def discover_notion_tables() -> List[Dict[str, Any]]:
    """Discover all main notion_* tables."""
    
    # Find main tables
    main_tables_sql = """
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'notion_sync'
        AND table_name LIKE 'notion_%'
        AND table_name NOT LIKE '%__%'
        AND table_name NOT IN ('_dlt_loads', '_dlt_pipeline_state', '_dlt_version')
        ORDER BY table_name;
    """
    
    tables = run_docker_sql(main_tables_sql)
    discovered_databases = []
    
    for (table_name,) in tables:
        # Extract database hash
        table_hash = table_name.replace('notion_', '')
        
        # Get row counts
        count_sql = f"""
            SELECT 
                COUNT(*) as total_rows,
                COUNT(CASE WHEN archived = false OR archived IS NULL THEN 1 END) as active_rows
            FROM notion_sync.{table_name};
        """
        
        try:
            count_result = run_docker_sql(count_sql)
            if count_result:
                row_count, active_rows = count_result[0]
                row_count = int(row_count.strip())
                active_rows = int(active_rows.strip())
            else:
                row_count = active_rows = 0
        except:
            row_count = active_rows = 0
        
        # Try to find a title property
        title_sql = f"""
            SELECT column_name 
            FROM information_schema.columns 
            WHERE table_schema = 'notion_sync'
            AND table_name = '{table_name}'
            AND column_name LIKE 'properties%title%'
            LIMIT 1;
        """
        
        try:
            title_result = run_docker_sql(title_sql)
            title_column = title_result[0][0] if title_result else None
        except:
            title_column = None
        
        # Create friendly name mapping based on known tables
        friendly_names = {
            '74f924b4672b4c0ead16511cdfe69396': 'categories',
            '8931b2899f7848d3bcd13e9b05aae69b': 'books', 
            'b981dec447fb4060877505e8cc63a45c': 'facts'
        }
        
        database_info = {
            'database_id': table_hash,
            'table_name': table_name,
            'friendly_name': friendly_names.get(table_hash, table_hash[:8]),
            'row_count': row_count,
            'active_rows': active_rows,
            'has_title_property': title_column is not None,
            'title_column': title_column
        }
        
        discovered_databases.append(database_info)
    
    return discovered_databases

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
    print("🔍 Discovering Notion databases from Docker...")
    
    try:
        # Discover main tables
        databases = discover_notion_tables()
        print(f"Found {len(databases)} Notion databases:")
        
        for db in databases:
            print(f"  • {db['friendly_name']} ({db['table_name']}) - {db['active_rows']} active records")
        
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
        
    except Exception as e:
        print(f"❌ Error: {e}")
        return 1
    
    return 0

if __name__ == '__main__':
    exit(main()) 