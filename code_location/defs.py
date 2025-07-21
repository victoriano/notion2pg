from dagster import asset, Definitions, ScheduleDefinition, define_asset_job
import dlt, os

DB_IDS = [db.strip() for db in os.getenv("NOTION_DB_ID", "").split(",") if db]
PG_URL = (
    f"postgresql://{os.getenv('PGUSER')}:{os.getenv('PGPASSWORD')}"
    f"@{os.getenv('PGHOST')}:{os.getenv('PGPORT')}/{os.getenv('PGDATABASE')}"
)

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
            data = resp.json()
            yield data["results"]
            if not data.get("has_more"):
                break
            payload["start_cursor"] = data["next_cursor"]

    return notion_pages

@asset(name="notion_sync")
def notion_sync_asset(context):
    pipeline = dlt.pipeline(
        pipeline_name="notion_to_pg",
        destination="postgres",
        dataset_name="notion_sync",
        credentials=PG_URL,
        max_db_connections=2,
    )
    for db in DB_IDS:
        info = pipeline.run(make_notion_resource(db)())
        context.log.info(f"Loaded {info.load_packages[-1].row_count} rows from {db}")

# Create a job that materializes the asset
notion_sync_job = define_asset_job(
    "notion_sync_job",
    selection=[notion_sync_asset]
)

schedule = ScheduleDefinition(
    job=notion_sync_job,
    cron_schedule="30 04 * * *",  # 04:30 Europe/Madrid
    execution_timezone="Europe/Madrid",
)

defs = Definitions(
    assets=[notion_sync_asset], 
    jobs=[notion_sync_job],
    schedules=[schedule]
) 