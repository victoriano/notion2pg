PDR – Notion → Postgres sync with dlt & Dagster

Goal: Build a reproducible stack that incrementally ingests one or more Notion databases into a dedicated Postgres warehouse, with full run traceability via Dagster. First run it locally on macOS (using Orbstack), then move the exact same containers to a Hetzner VPS.

⸻

1 · Scope
	•	Included: dlt pipelines, Postgres (as a container), Dagster OSS, logical backups, minimal monitoring.
	•	Excluded: alternative orchestrators (Airflow, Prefect), non-Hetzner IaaS, BI/visualisation layers.

⸻

2 · Architecture

┌─────────────── Local laptop (macOS + Orbstack) ───────────────┐
│ docker-compose (Orbstack runtime)                             │
│ ├─ postgres_dwh      ← data from Notion                       │
│ ├─ dagster_web                                          3000 │
│ ├─ dagster_daemon                                             │
│ └─ code_location  ← dlt pipeline (GRPC)                       │
└───────────────────────────────────────────────────────────────┘

┌───────────────────────── Hetzner VPS ─────────────────────────┐
│ Same compose stack + persistent volumes + snapshots + FW      │
└───────────────────────────────────────────────────────────────┘


⸻

3 · Requirements

Environment	Minimum spec
Local	macOS 14+, Orbstack ≥ 0.18 (Docker & Compose drop-in), 4 GB free RAM, open ports 5432, 3000
Production	Ubuntu 22.04 LTS on a Hetzner CX11 (1 vCPU / 2 GB RAM / 20 GB SSD), snapshot quota enabled

Environment variables required in .env:

NOTION_TOKEN        # internal integration token
NOTION_DB_ID        # comma-separated list of database IDs
PGUSER, PGPASSWORD  # Postgres superuser


⸻

4 · Repository layout

notion_sync/
├─ code_location/
│  ├─ Dockerfile
│  ├─ requirements.txt
│  └─ defs.py           ← Dagster assets + dlt pipeline
├─ docker-compose.yml
├─ .env.example
└─ pipeline_state/      ← persistent .dlt state


⸻

5 · Key files

5.1 .env.example

# Notion
NOTION_TOKEN=secret_xxx
NOTION_DB_ID=111aaa,222bbb,333ccc

# Local Postgres (container)
PGUSER=postgres
PGPASSWORD=supersecret
PGHOST=postgres_dwh
PGPORT=5432
PGDATABASE=analytics

# Dagster metadata DB (same instance)
DAGSTER_DB=dagster_meta

5.2 docker-compose.yml

version: "3.9"

services:
  postgres_dwh:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: ${PGUSER}
      POSTGRES_PASSWORD: ${PGPASSWORD}
      POSTGRES_DB: ${PGDATABASE}
    volumes:
      - pg_data:/var/lib/postgresql/data
    deploy:
      resources:
        limits:
          memory: 512M

  dagster_web:
    image: dagster/dagster-webserver:1.8.1
    environment:
      DAGSTER_POSTGRES_HOST: postgres_dwh
      DAGSTER_POSTGRES_DB: ${DAGSTER_DB}
      DAGSTER_POSTGRES_USER: ${PGUSER}
      DAGSTER_POSTGRES_PASSWORD: ${PGPASSWORD}
    ports: ["3000:3000"]
    depends_on: [code]

  dagster_daemon:
    image: dagster/dagster-daemon:1.8.1
    environment:
      DAGSTER_POSTGRES_HOST: postgres_dwh
      DAGSTER_POSTGRES_DB: ${DAGSTER_DB}
      DAGSTER_POSTGRES_USER: ${PGUSER}
      DAGSTER_POSTGRES_PASSWORD: ${PGPASSWORD}
    depends_on: [postgres_dwh]
    restart: unless-stopped

  code:
    build: ./code_location
    env_file: .env
    volumes:
      - ./pipeline_state:/app/.dlt
    restart: "no"

volumes:
  pg_data:

5.3 code_location/requirements.txt

dagster==1.8.1
dlt>=0.5
psycopg2-binary

5.4 code_location/Dockerfile

FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["dagster", "api", "grpc", "-m", "defs"]

5.5 code_location/defs.py

from dagster import asset, Definitions, ScheduleDefinition
import dlt, os

DB_IDS = [db.strip() for db in os.getenv("NOTION_DB_ID", "").split(",") if db]
PG_URL = (
    f"postgres://{os.getenv('PGUSER')}:{os.getenv('PGPASSWORD')}"
    f"@{os.getenv('PGHOST')}:{os.getenv('PGPORT')}/{os.getenv('PGDATABASE')}"
)

def make_notion_resource(db_id: str):
    @dlt.resource(
        name=f"notion_{db_id}",
        primary_key="id",
        write_disposition={"disposition": "merge", "strategy": "upsert"}
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

schedule = ScheduleDefinition(
    job=notion_sync_asset,  # asset → implicit job
    cron_schedule="30 04 * * *",  # 04:30 Europe/Madrid
    execution_timezone="Europe/Madrid",
)

defs = Definitions(assets=[notion_sync_asset], schedules=[schedule])


⸻

6 · Local run with Orbstack

# Clone repo and set secrets
git clone git@github.com:yourorg/notion_sync.git
cd notion_sync && cp .env.example .env   # fill keys

# Build images (Orbstack uses same CLI)
orbstack compose build code              # ← alias for docker compose

# Spin-up services (Postgres + Dagster) in background
orbstack compose up -d postgres_dwh dagster_web dagster_daemon

# Open UI
open http://localhost:3000  # Dagster web

# Register location: Add → Docker → code_location
# Trigger a manual run or enable the schedule in the UI.

Orbstack mounts volumes under ~/Library/Containers/orb.local/...; no changes required in docker-compose.yml.

⸻

7 · Deploy to Hetzner

# 1) create server (CLI example)
hcloud server create --type cx11 --image ubuntu-22.04 --name notion-sync

# 2) install Docker/Compose
ssh root@your_ip "curl -fsSL https://get.docker.com | sh"

# 3) copy project & env
scp -r notion_sync root@your_ip:/opt/
ssh root@your_ip "cd /opt/notion_sync && cp .env.example .env && nano .env"  # fill tokens

# 4) run stack
ssh root@your_ip "cd /opt/notion_sync && docker compose up -d"

# 5) harden firewall (only 22 & 3000 whitelisted)

Snapshots or restic backups for pg_data are highly recommended.

⸻

8 · Ops & maintenance

Task	Command
Update images	docker compose pull && docker compose up -d --build
Manual backup	`pg_dump -U postgres analytics
Rotate Dagster logs	configure logrotate on host
Scale VPS	resize to CX22 (4 GB) and raise shared_buffers to 256 MB


⸻

9 · Next steps
	1.	Add unit tests with pytest + dagster dev.
	2.	Configure @run_failure_sensor to push alerts to Slack.
	3.	Expand to other APIs (same asset pattern).
	4.	Introduce dbt models downstream.

⸻

Generated for Victoriano · July 2025