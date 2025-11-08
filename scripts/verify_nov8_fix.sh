#!/bin/bash
# ============================================================================
# Project Chronos: Database Verification Script (Fixed)
# ============================================================================

set -e

CONTAINER_NAME="chronos-db"
DB_NAME="chronos_db"
DB_USER="prometheus"

echo "=================================================="
echo "Project Chronos: Database Verification"
echo "=================================================="
echo ""

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check container running
echo "📦 Checking if database container is running..."
if ! docker ps | grep -q "$CONTAINER_NAME"; then
    echo -e "${RED}❌ Container not running${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Container is running${NC}"
echo ""

# Check database ready
echo "🔌 Checking if database is accepting connections..."
if ! docker exec "$CONTAINER_NAME" pg_isready -U "$DB_USER" -d "$DB_NAME" > /dev/null 2>&1; then
    echo -e "${RED}❌ Database is not ready${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Database is ready${NC}"
echo ""

# Check extensions (FIX: Strip whitespace)
echo "🔧 Checking PostgreSQL extensions..."
EXTENSIONS=$(docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM pg_extension WHERE extname IN ('timescaledb', 'postgis', 'vector', 'age');" | tr -d ' \n\r')
echo "   Found: $EXTENSIONS extensions"
if [ "$EXTENSIONS" -eq 4 ]; then
    echo -e "${GREEN}✅ All 4 required extensions installed${NC}"
else
    echo -e "${RED}❌ ERROR: Only $EXTENSIONS/4 extensions found${NC}"
    echo ""
    echo "Installed extensions:"
    docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT extname FROM pg_extension WHERE extname IN ('timescaledb', 'postgis', 'vector', 'age');"
    exit 1
fi
echo ""

# Check AGE graph (FIX: Strip whitespace)
echo "📊 Checking Apache AGE graph..."
GRAPH_COUNT=$(docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM ag_catalog.ag_graph WHERE name = 'economic_graph';" | tr -d ' \n\r')
echo "   Found: $GRAPH_COUNT graph(s)"
if [ "$GRAPH_COUNT" -eq 1 ]; then
    echo -e "${GREEN}✅ Graph 'economic_graph' exists${NC}"
else
    echo -e "${RED}❌ ERROR: Graph 'economic_graph' not found${NC}"
    echo ""
    echo "Available graphs:"
    docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT name FROM ag_catalog.ag_graph;"
    exit 1
fi
echo ""

# Check vertex labels (FIX: Strip whitespace)
echo "🏷️  Checking vertex labels..."
VLABEL_COUNT=$(docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM ag_catalog.ag_label WHERE graph = (SELECT graphid FROM ag_catalog.ag_graph WHERE name = 'economic_graph') AND kind = 'v';" | tr -d ' \n\r')
echo "   Found: $VLABEL_COUNT vertex labels"
if [ "$VLABEL_COUNT" -ge 2 ]; then
    echo -e "${GREEN}✅ Found $VLABEL_COUNT vertex labels${NC}"
else
    echo -e "${YELLOW}⚠️  WARNING: Only $VLABEL_COUNT vertex labels found${NC}"
fi
echo ""

# Check hypertable (FIX: Strip whitespace)
echo "⏱️  Checking TimescaleDB hypertable..."
HYPERTABLE=$(docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM timescaledb_information.hypertables WHERE hypertable_name = 'economic_observations';" | tr -d ' \n\r')
if [ "$HYPERTABLE" -eq 1 ]; then
    echo -e "${GREEN}✅ Hypertable 'economic_observations' exists${NC}"
else
    echo -e "${RED}❌ ERROR: Hypertable not found${NC}"
    exit 1
fi
echo ""

echo "=================================================="
echo -e "${GREEN}🎉 All critical checks passed!${NC}"
echo "=================================================="
echo ""
echo "✅ Database is healthy and ready"
echo ""
