#!/usr/bin/env python3
"""
Project Chronos: FRED Data Ingestion Script
============================================
Purpose: Command-line script to ingest FRED data into Chronos database

Usage:
    python src/scripts/ingest_fred.py --series GDP UNRATE
    python src/scripts/ingest_fred.py --series GDP --start-date 2020-01-01
"""

import sys
from datetime import datetime
from pathlib import Path
from typing import List, Optional

import click
from sqlalchemy import text

# Add src directory to Python path
sys.path.insert(0, str(Path(__file__).parent.parent))

from chronos.database.connection import get_db_session, verify_database_connection
from chronos.ingestion.fred import FREDIngestor
from chronos.utils.logging import get_logger
from chronos.utils.exceptions import ChronosBaseException

logger = get_logger(__name__)


def log_ingestion_start(session, source_id: int, series_ids: List[str]) -> int:
    """Create ingestion log entry at start of process."""
    result = session.execute(
        text("""
            INSERT INTO metadata.ingestion_log (
                source_id, ingestion_start, status, series_count
            )
            VALUES (:source_id, NOW(), 'running', :series_count)
            RETURNING log_id
        """),
        {"source_id": source_id, "series_count": len(series_ids)}
    )
    log_id = result.fetchone()[0]
    # NOTE: We commit here because this is a separate transaction from data ingestion
    session.commit()
    return log_id


def log_ingestion_end(
    session,
    log_id: int,
    status: str,
    records_inserted: int,
    error_message: Optional[str] = None
) -> None:
    """Update ingestion log entry at end of process."""
    session.execute(
        text("""
            UPDATE metadata.ingestion_log
            SET ingestion_end = NOW(),
                status = :status,
                records_inserted = :records_inserted,
                error_message = :error_message
            WHERE log_id = :log_id
        """),
        {
            "log_id": log_id,
            "status": status,
            "records_inserted": records_inserted,
            "error_message": error_message
        }
    )
    # NOTE: We commit here because this is a separate transaction from data ingestion
    session.commit()


@click.command()
@click.option(
    "--series",
    "-s",
    multiple=True,
    required=True,
    help="FRED series IDs to ingest (e.g., GDP, UNRATE)"
)
@click.option(
    "--start-date",
    type=click.DateTime(formats=["%Y-%m-%d"]),
    help="Start date for observations (YYYY-MM-DD)"
)
@click.option(
    "--end-date",
    type=click.DateTime(formats=["%Y-%m-%d"]),
    help="End date for observations (YYYY-MM-DD)"
)
@click.option(
    "--verify-only",
    is_flag=True,
    help="Only verify database connection"
)
def main(
    series: tuple,
    start_date: Optional[datetime],
    end_date: Optional[datetime],
    verify_only: bool
) -> None:
    """Ingest FRED macroeconomic data into Chronos database."""
    
    logger.info(
        "ingestion_started",
        series_ids=list(series),
        start_date=start_date.date() if start_date else None,
        end_date=end_date.date() if end_date else None
    )
    
    # Verify Database Connection
    if not verify_database_connection():
        logger.error("database_verification_failed")
        click.echo("❌ Database connection failed", err=True)
        sys.exit(1)
    
    click.echo("✅ Database connection verified")
    
    if verify_only:
        click.echo("✅ Verification complete")
        sys.exit(0)
    
    # Initialize variables
    total_records = 0
    log_id = None
    
    try:
        # IMPORTANT: Single transaction scope for all data operations
        with get_db_session() as session:
            ingestor = FREDIngestor(session)
            
            # Log ingestion start (separate transaction)
            log_id = log_ingestion_start(session, ingestor.source_id, list(series))
            click.echo(f"📊 Ingestion log ID: {log_id}")
            
            # Fetch and Register Series Metadata
            click.echo(f"\n🔍 Fetching metadata for {len(series)} series...")
            metadata_list = ingestor.fetch_series_metadata(list(series))
            
            if not metadata_list:
                raise ChronosBaseException("No valid series metadata retrieved")
            
            click.echo(f"✅ Retrieved metadata for {len(metadata_list)} series")
            
            # Ingest Observations for Each Series
            for metadata in metadata_list:
                source_series_id = metadata["source_series_id"]
                click.echo(f"\n📥 Processing: {source_series_id}")
                click.echo(f"   {metadata['series_name']}")
                
                # Register series (no internal commit)
                series_id = ingestor.register_series(metadata)
                click.echo(f"   Series ID: {series_id}")
                
                # Fetch observations
                observations = ingestor.fetch_observations(
                    source_series_id,
                    start_date=start_date,
                    end_date=end_date
                )
                
                if not observations:
                    click.echo(f"   ⚠️  No observations found")
                    continue
                
                # Store observations (no internal commit)
                records_count = ingestor.store_observations(series_id, observations)
                total_records += records_count
                
                click.echo(f"   ✅ Stored {records_count} observations")
                click.echo(f"   📅 {observations[0]['date']} to {observations[-1]['date']}")
            
            # Transaction automatically committed here by get_db_session()
        
        # Finalize ingestion log (separate transaction)
        with get_db_session() as session:
            log_ingestion_end(session, log_id, "success", total_records)
        
        click.echo(f"\n{'='*60}")
        click.echo(f"✅ Ingestion complete!")
        click.echo(f"   Series processed: {len(metadata_list)}")
        click.echo(f"   Observations stored: {total_records}")
        click.echo(f"   Log ID: {log_id}")
        click.echo(f"{'='*60}")
        
        logger.info(
            "ingestion_completed",
            series_count=len(metadata_list),
            records_inserted=total_records
        )
    
    except ChronosBaseException as e:
        error_msg = f"Ingestion failed: {str(e)}"
        logger.error("ingestion_failed", error=str(e))
        click.echo(f"\n❌ {error_msg}", err=True)
        
        if log_id:
            try:
                with get_db_session() as session:
                    log_ingestion_end(session, log_id, "failed", total_records, error_msg)
            except Exception:
                pass
        
        sys.exit(1)
    
    except Exception as e:
        error_msg = f"Unexpected error: {str(e)}"
        logger.error("ingestion_error_unexpected", error=str(e))
        click.echo(f"\n❌ {error_msg}", err=True)
        
        if log_id:
            try:
                with get_db_session() as session:
                    log_ingestion_end(session, log_id, "failed", total_records, error_msg)
            except Exception:
                pass
        
        sys.exit(1)


if __name__ == "__main__":
    main()