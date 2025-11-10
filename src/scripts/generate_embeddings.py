#!/usr/bin/env python3
"""Generate embeddings for series descriptions using sentence-transformers."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from sentence_transformers import SentenceTransformer
from sqlalchemy import text
from chronos.database.connection import get_db_session


def generate_embeddings():
    """Generate and store embeddings for all series."""
    model = SentenceTransformer("all-MiniLM-L6-v2")

    with get_db_session() as session:
        # Fetch series without embeddings
        result = session.execute(
            text(
                """
            SELECT series_id, series_description
            FROM metadata.series_metadata
            WHERE description_embedding IS NULL
            AND series_description IS NOT NULL
        """
            )
        )

        series_list = result.fetchall()
        print(f"Found {len(series_list)} series needing embeddings")

        for series_id, description in series_list:
            # Generate embedding
            embedding = model.encode(description)

            # FIXED: Use parameterized query (prevents SQL injection)
            session.execute(
                text(
                    """
                    UPDATE metadata.series_metadata
                    SET description_embedding = :embedding::vector
                    WHERE series_id = :series_id
                """
                ),
                {"embedding": embedding.tolist(), "series_id": series_id},
            )
            print(f"✅ Generated embedding for series {series_id}")

        session.commit()
        print(f"\n✅ Generated {len(series_list)} embeddings")


if __name__ == "__main__":
    generate_embeddings()
