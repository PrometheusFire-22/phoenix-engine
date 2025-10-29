#!/bin/bash
echo "Script started"
cd /home/prometheus/coding/finance/project-chronos
source venv/bin/activate
export PYTHONPATH="$(pwd)/src"
echo "Running ingestion..."
python src/scripts/ingest_fred.py --series GDP --verify-only
echo "Done"
