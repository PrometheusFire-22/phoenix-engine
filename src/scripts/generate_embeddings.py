# src/scripts/generate_embeddings.py
"""
Generates and stores sentence embeddings for series descriptions.
"""
from chronos.utils.logging import get_logger
from chronos.database.connection import get_db_session
import sys
import pandas as pd
from sqlalchemy import text
from sentence_transformers import SentenceTransformer

# Ensure the 'src' directory is in the Python path
sys.path.insert(0, ".")

logger = get_logger(__name__)


def generate_and_store_embeddings():
    """
    Fetches series without embeddings, generates them, and updates the database.
    """
    model = SentenceTransformer("all-MiniLM-L6-v2")
    logger.info("SentenceTransformer model loaded.")

    query = text(
        """
        SELECT series_id, description
        FROM metadata.series_metadata
        WHERE description IS NOT NULL AND description_embedding IS NULL
    """
    )

    try:
        with get_db_session() as session:
            df = pd.read_sql_query(query, session.bind)
            if df.empty:
                logger.info("No new series descriptions to embed. Exiting.")
                return

            logger.info(f"Found {len(df)} series to process.")
            embeddings = model.encode(df["description"].tolist(), show_progress_bar=True)

            update_count = 0
            for index, row in df.iterrows():
                series_id = row["series_id"]
                embedding = embeddings[index]

                # --- CORRECTED SQL EXECUTION ---
                # Use parameterized queries to prevent SQL injection
                update_query = text(
                    """
                    UPDATE metadata.series_metadata
                    SET description_embedding = :embedding
                    WHERE series_id = :series_id
                """
                )
                session.execute(
                    update_query,
                    {
                        # Cast list to string for pgvector
                        "embedding": str(embedding.tolist()),
                        "series_id": series_id,
                    },
                )
                update_count += 1

            session.commit()
            logger.info(f"Successfully updated {update_count} series with embeddings.")

    except Exception as e:
        logger.error(f"An error occurred during embedding generation: {e}", exc_info=True)
        # The session context manager will handle rollback


if __name__ == "__main__":
    generate_and_store_embeddings()
