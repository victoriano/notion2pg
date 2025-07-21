# 🚀 Testing Your Dagster + dbt Pipeline

## Quick Test Guide

### 1. Access Dagster UI
Open your browser and go to:
```
http://localhost:3000
```

### 2. Run the Full Pipeline
1. Click on **"Jobs"** in the left sidebar
2. Find **"full_pipeline_job"**
3. Click **"Launch Run"** button
4. Watch the pipeline execute!

### 3. What to Expect
The pipeline will run in this order:

```
📊 notion_sync_asset (1-2 minutes)
    ↓
📈 dbt_marts_refresh_asset (10-30 seconds)
```

### 4. Monitor Progress
- **Green**: Asset is running
- **Blue**: Asset completed successfully
- **Red**: Asset failed (check logs)

### 5. Verify Results

After successful run, check your refreshed data:

```bash
# Check categories with emojis
docker exec -i notion2pg-postgres_dwh-1 psql -U postgres -d analytics -c "
SELECT icon_emoji, name, total_facts_count 
FROM notion_views_marts.categories_view_complete 
WHERE icon_emoji IS NOT NULL 
ORDER BY total_facts_count DESC 
LIMIT 10;"

# Check books
docker exec -i notion2pg-postgres_dwh-1 psql -U postgres -d analytics -c "
SELECT substring(title, 1, 30) as title, category_count 
FROM notion_views_marts.books_view_complete 
ORDER BY category_count DESC 
LIMIT 5;"

# Check facts
docker exec -i notion2pg-postgres_dwh-1 psql -U postgres -d analytics -c "
SELECT COUNT(*) as total_facts 
FROM notion_views_marts.facts_view_complete;"
```

### 6. Check Individual Assets
You can also run assets individually:
- Click **"Assets"** in the sidebar
- Find **"notion_sync"** or **"dbt_marts_refresh"**
- Click **"Materialize"** to run just that asset

### 7. View Logs
1. Click on any completed run
2. Click on an asset
3. View **"Logs"** tab for detailed execution logs

### 8. Schedule Status
Check the schedule is active:
1. Click **"Schedules"** in sidebar
2. Verify **"full_pipeline_schedule"** shows as **ON**
3. Next run: 04:30 Europe/Madrid

## Troubleshooting

### If dbt fails:
```bash
# Check dbt can connect to database
cd dbt_project/notion_views
dbt debug --profiles-dir .

# Run dbt manually to see errors
dbt run --profiles-dir .
```

### If notion_sync fails:
- Check your NOTION_TOKEN in .env
- Verify NOTION_DB_ID values are correct
- Check Notion API access

### Common Issues:
1. **"No module named 'dbt'"** - Restart services
2. **"Database connection failed"** - Check PostgreSQL is running
3. **"Asset not found"** - Reload Dagster UI

## Success Indicators ✅
- ✅ Both assets show blue (completed)
- ✅ Logs show "dbt run completed successfully"
- ✅ Categories have emojis (🇪🇸, 🤯, 🏦)
- ✅ Marts tables are updated with fresh data

## Next Steps
After successful test:
1. Monitor daily runs at 04:30 Madrid time
2. Add data quality tests
3. Create dashboards from marts
4. Enjoy your automated pipeline! 🎉

---
**Your pipeline is ready to test!** Go to http://localhost:3000 and launch the full_pipeline_job! 🚀 