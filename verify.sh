#!/bin/bash

echo "--- 🕵️ Project Chronos Verification Script ---"

# --- 1. Docker Health Check ---
echo -e "\n--- 1. Checking Docker Containers... ---"
if ! docker compose ps > /dev/null 2>&1; then
    echo "❌ CRITICAL: Docker is not running or docker-compose is not configured."
    exit 1
fi

FRONTEND_STATUS=$(docker compose ps | grep chronos-frontend | awk '{print $5}')
DB_STATUS=$(docker compose ps | grep chronos-db | awk '{print $6}')

if [[ "$FRONTEND_STATUS" == "Up" ]]; then
    echo "✅ Frontend container is RUNNING."
else
    echo "❌ Frontend container is NOT running. Status: ${FRONTEND_STATUS:-Exited}. Checking logs..."
    docker compose logs frontend
    echo "--- End of Frontend Logs ---"
fi

if [[ "$DB_STATUS" == "(healthy)" ]]; then
    echo "✅ Database container is RUNNING and HEALTHY."
else
    echo "❌ Database container is NOT healthy. Status: ${DB_STATUS}. Checking logs..."
    docker compose logs timescaledb
    echo "--- End of Database Logs ---"
fi

if [[ "$DB_STATUS" != "(healthy)" ]]; then
    echo -e "\n🔥 Halting verification due to database container issues."
    exit 1
fi

# --- 2. Database Schema & Data Check ---
echo -e "\n--- 2. Verifying Database State... ---"
DB_EXEC="docker exec -it chronos-db psql -U ${DATABASE_USER} -d ${DATABASE_NAME} -c"

echo "Checking extensions..."
EXT_COUNT=$($DB_EXEC "SELECT COUNT(*) FROM pg_extension WHERE extname IN ('timescaledb', 'postgis', 'vector', 'age');" 2>/dev/null | sed -n 3p | tr -d '[:space:]')
if [[ "$EXT_COUNT" -eq 4 ]]; then
    echo "✅ All 4 key extensions are installed."
else
    echo "❌ FAILED: Found only ${EXT_COUNT:-0} out of 4 key extensions."
fi

echo "Checking seed data..."
SOURCE_COUNT=$($DB_EXEC "SELECT COUNT(*) FROM metadata.data_sources WHERE source_name IN ('FRED', 'VALET');" 2>/dev/null | sed -n 3p | tr -d '[:space:]')
if [[ "$SOURCE_COUNT" -eq 2 ]]; then
    echo "✅ FRED and VALET data sources are present."
else
    echo "❌ FAILED: Found only ${SOURCE_COUNT:-0} out of 2 required data sources."
fi

echo "Checking analytics functions..."
FUNC_EXISTS=$($DB_EXEC "SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_latest_observations');" 2>/dev/null | sed -n 3p | tr -d '[:space:]')
if [[ "$FUNC_EXISTS" == "t" ]]; then
    echo "✅ Analytics function 'get_latest_observations' exists."
else
    echo "❌ FAILED: Analytics functions are missing."
fi

echo -e "\n--- ✅ Verification Complete ---"
