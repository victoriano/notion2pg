from dagster import asset, Definitions, ScheduleDefinition, define_asset_job, AssetExecutionContext, AssetIn
import dlt, os
from pathlib import Path
import subprocess

# Configuration
DB_IDS = [db.strip() for db in os.getenv("NOTION_DB_ID", "").split(",") if db]
PG_URL = (
    f"postgresql://{os.getenv('PGUSER')}:{os.getenv('PGPASSWORD')}"
    f"@{os.getenv('PGHOST')}:{os.getenv('PGPORT')}/{os.getenv('PGDATABASE')}"
)

# dbt project configuration - use mounted volume path
dbt_project_dir = Path("/opt/dagster/dbt_project/notion_views")

def make_notion_resource(db_id: str):
    @dlt.resource(
        name=f"notion_{db_id}",
        primary_key="id",
        write_disposition="merge"
    )
    def notion_pages(cursor=dlt.sources.incremental("last_edited_time", initial_value="1970-01-01T00:00:00Z")):
        import requests
        url = f"https://api.notion.com/v1/databases/{db_id}/query"
        headers = {
            "Authorization": f"Bearer {os.getenv('NOTION_TOKEN')}",
            "Notion-Version": "2022-06-28",
            "Content-Type": "application/json",
        }
        payload = {
            "sorts": [{"timestamp": "last_edited_time", "direction": "descending"}],
            "page_size": 100,
            "filter": {
                "timestamp": "last_edited_time",
                "last_edited_time": {"after": cursor.start_value},
            },
        }
        while True:
            resp = requests.post(url, headers=headers, json=payload, timeout=30)
            
            # Check for HTTP errors
            if resp.status_code != 200:
                raise Exception(f"Notion API error for database {db_id}: HTTP {resp.status_code} - {resp.text}")
            
            data = resp.json()
            
            # Check for API errors in response
            if "object" in data and data["object"] == "error":
                raise Exception(f"Notion API error for database {db_id}: {data.get('code', 'unknown')} - {data.get('message', 'no message')}")
            
            # Check for expected results structure
            if "results" not in data:
                raise Exception(f"Unexpected Notion API response for database {db_id}. Response keys: {list(data.keys())}. Full response: {data}")
            
            yield data["results"]
            if not data.get("has_more"):
                break
            payload["start_cursor"] = data["next_cursor"]

    return notion_pages

@asset(name="notion_sync")
def notion_sync_asset(context: AssetExecutionContext):
    """Sync data from Notion databases to PostgreSQL"""
    pipeline = dlt.pipeline(
        pipeline_name="notion_to_pg",
        destination="postgres",
        dataset_name="notion_sync",
    )
    for db in DB_IDS:
        info = pipeline.run(
            make_notion_resource(db)(),
            credentials=PG_URL
        )
        context.log.info(f"Successfully synced database {db} - Pipeline info: {info.pipeline.pipeline_name}")

# Simple dbt asset that depends on notion_sync
@asset(
    name="dbt_marts_refresh",
    ins={"notion_sync": AssetIn("notion_sync")}
)
def dbt_marts_refresh_asset(context: AssetExecutionContext, notion_sync):
    """
    Run all dbt models to refresh marts after Notion sync.
    This creates clean, business-ready views from raw Notion data.
    """
    # Log that we're starting dbt after notion sync
    context.log.info("Starting dbt transformation after successful Notion sync")
    
    # Run dbt using subprocess in the dbt project directory
    try:
        # Set environment variables for dbt to connect to the database
        env = os.environ.copy()
        env.update({
            'PGHOST': os.getenv('PGHOST', 'postgres_dwh'),
            'PGPORT': os.getenv('PGPORT', '5432'),
            'PGDATABASE': os.getenv('PGDATABASE', 'analytics'),
            'PGUSER': os.getenv('PGUSER', 'postgres'),
            'PGPASSWORD': os.getenv('PGPASSWORD'),
        })
        
        # Run dbt
        result = subprocess.run(
            ["dbt", "run", "--profiles-dir", ".", "--no-version-check"],
            cwd=dbt_project_dir,
            capture_output=True,
            text=True,
            env=env
        )
        
        # Log output
        context.log.info(f"dbt stdout:\n{result.stdout}")
        
        if result.returncode != 0:
            context.log.error(f"dbt stderr:\n{result.stderr}")
            raise Exception(f"dbt run failed with return code {result.returncode}")
        
        # Parse success from output
        if "Completed successfully" in result.stdout:
            # Extract number of models from output
            import re
            models_match = re.search(r'PASS=(\d+)', result.stdout)
            models_count = models_match.group(1) if models_match else "unknown"
            
            context.log.info(f"dbt run completed successfully. {models_count} models executed.")
            return f"Successfully refreshed {models_count} dbt models"
        else:
            raise Exception("dbt run did not complete successfully")
            
    except Exception as e:
        context.log.error(f"Error running dbt: {str(e)}")
        raise

# Create jobs
notion_sync_job = define_asset_job(
    "notion_sync_job",
    selection=[notion_sync_asset]
)

# Job that runs both sync and dbt transformation
full_pipeline_job = define_asset_job(
    "full_pipeline_job", 
    selection=[notion_sync_asset, dbt_marts_refresh_asset],
    description="Complete pipeline: sync from Notion + refresh dbt marts"
)

# Schedule for the full pipeline (sync + dbt)
full_pipeline_schedule = ScheduleDefinition(
    job=full_pipeline_job,
    cron_schedule="30 04 * * *",  # 04:30 Europe/Madrid
    execution_timezone="Europe/Madrid",
    description="Daily sync from Notion followed by dbt mart refresh"
)

defs = Definitions(
    assets=[notion_sync_asset, dbt_marts_refresh_asset],
    jobs=[notion_sync_job, full_pipeline_job],
    schedules=[full_pipeline_schedule]
) 