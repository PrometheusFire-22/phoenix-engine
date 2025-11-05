#!/usr/bin/env python3
"""
Generate vector embeddings for series descriptions using sentence-transformers.

This script:
1. Loads the all-MiniLM-L6-v2 model (384 dimensions)
2. Fetches series metadata from the database
3. Generates embeddings for series descriptions
4. Updates the description_embedding column in series_metadata

Cost: $0 (completely free, runs locally)
Time: ~10 seconds for 52 series
"""

import sys
from pathlib import Path

# Add src to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from sentence_transformers import SentenceTransformer
from sqlalchemy import text
from chronos.database.connection import get_db_session
from chronos.utils.logging import get_logger

logger = get_logger(__name__)


def generate_embeddings():
    """Generate and store embeddings for all series descriptions."""

    logger.info("Loading sentence-transformers model...")
    model = SentenceTransformer("all-MiniLM-L6-v2")
    logger.info("Model loaded successfully (384 dimensions)")

    with get_db_session() as session:
        # Fetch all series with descriptions
        result = session.execute(
            text(
                """
                SELECT
                    series_id,
                    source_series_id,
                    series_name,
                    description
                FROM metadata.series_metadata
                WHERE description IS NOT NULL
                ORDER BY series_id
            """
            )
        )
        series = result.fetchall()

        logger.info(f"Found {len(series)} series with descriptions")

        if not series:
            logger.warning("No series found with descriptions!")
            return

        # Generate embeddings
        descriptions = [row[3] for row in series]
        logger.info("Generating embeddings...")
        embeddings = model.encode(descriptions, show_progress_bar=True)

        # Update database
        logger.info("Updating database...")
        updated_count = 0

        for (series_id, source_series_id, series_name, _), embedding in zip(series, embeddings):
            # Convert numpy array to list for PostgreSQL
            embedding_list = embedding.tolist()

            session.execute(
                text(
                    """
                    UPDATE metadata.series_metadata
                    SET description_embedding = :embedding::vector
                    WHERE series_id = :series_id
                """
                ),
                {"embedding": str(embedding_list), "series_id": series_id},
            )
            updated_count += 1

            if updated_count % 10 == 0:
                logger.info(f"Updated {updated_count}/{len(series)} series")

        session.commit()
        logger.info(f"✅ Successfully generated embeddings for {updated_count} series")

        # Test similarity search
        logger.info("\n🔍 Testing semantic search...")
        test_query = "inflation indicators"
        query_embedding = model.encode([test_query])[0].tolist()

        result = session.execute(
            text(
                """
                SELECT
                    source_series_id,
                    series_name,
                    1 - (description_embedding <=> :query_embedding::vector) as similarity
                FROM metadata.series_metadata
                WHERE description_embedding IS NOT NULL
                ORDER BY description_embedding <=> :query_embedding::vector
                LIMIT 5
            """
            ),
            {"query_embedding": str(query_embedding)},
        )

        logger.info(f"\nTop 5 series similar to '{test_query}':")
        for row in result:
            logger.info(f"  {row[0]}: {row[1]} (similarity: {row[2]:.3f})")


if __name__ == "__main__":
    try:
        generate_embeddings()
    except Exception as e:
        logger.error(f"Failed to generate embeddings: {e}")
        raise
