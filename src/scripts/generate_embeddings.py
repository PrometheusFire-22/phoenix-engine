#!/usr/bin/env python3
"""Generate vector embeddings for series descriptions."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from sentence_transformers import SentenceTransformer
from sqlalchemy import text
from chronos.database.connection import get_db_session
from chronos.utils.logging import get_logger

logger = get_logger(__name__)

def generate_embeddings():
    logger.info("Loading sentence-transformers model...")
    model = SentenceTransformer("all-MiniLM-L6-v2")
    logger.info("Model loaded successfully (384 dimensions)")

    with get_db_session() as session:
        result = session.execute(text("""
            SELECT series_id, source_series_id, series_name, series_description
            FROM metadata.series_metadata
            WHERE series_description IS NOT NULL
            ORDER BY series_id
        """))
        series = result.fetchall()
        logger.info(f"Found {len(series)} series with descriptions")
        
        if not series:
            logger.warning("No series found!")
            return

        descriptions = [row[3] for row in series]
        logger.info("Generating embeddings...")
        embeddings = model.encode(descriptions, show_progress_bar=True)

        logger.info("Updating database...")
        for (series_id, source_series_id, series_name, _), embedding in zip(series, embeddings):
            # FIX: Use format string instead of :param syntax
            session.execute(text(f"""
                UPDATE metadata.series_metadata
                SET description_embedding = '{embedding.tolist()}'::vector
                WHERE series_id = {series_id}
            """))

        session.commit()
        logger.info(f"✅ Successfully generated embeddings for {len(series)} series")

if __name__ == "__main__":
    try:
        generate_embeddings()
    except Exception as e:
        logger.error(f"Failed: {e}")
        raise
