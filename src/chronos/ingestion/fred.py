"""
Project Chronos: FRED Data Ingestion
=====================================
Purpose: Ingest macroeconomic data from Federal Reserve Economic Data (FRED)
API Docs: https://fred.stlouisfed.org/docs/api/fred/
"""

from datetime import datetime
from typing import List, Dict, Any, Optional
import time

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from chronos.ingestion.base import BaseIngestor
from chronos.config.settings import settings
from chronos.utils.exceptions import APIError, RateLimitError


class FREDIngestor(BaseIngestor):
    """
    FRED API data ingestor.

    Features:
    - Automatic retry with exponential backoff
    - Rate limit handling (120 requests/minute)
    - Robust error handling
    """

    BASE_URL = "https://api.stlouisfed.org/fred"

    def __init__(self, session):
        super().__init__(session, source_name="FRED")
        self.api_key = settings.fred_api_key
        self.http_session = self._create_http_session()
        self.requests_made = 0
        self.last_request_time = None

    def _create_http_session(self) -> requests.Session:
        """Create HTTP session with retry logic."""
        session = requests.Session()

        # Retry strategy: 3 retries with exponential backoff
        retry_strategy = Retry(
            total=3,
            backoff_factor=1,
            status_forcelist=[429, 500, 502, 503, 504],
            allowed_methods=["GET"],
        )

        adapter = HTTPAdapter(max_retries=retry_strategy)
        session.mount("http://", adapter)
        session.mount("https://", adapter)

        return session

    def _rate_limit_check(self) -> None:
        """Enforce rate limiting (120 requests/minute for FRED)."""
        if self.last_request_time is not None:
            time_since_last = time.time() - self.last_request_time
            min_interval = 60.0 / settings.fred_rate_limit

            if time_since_last < min_interval:
                sleep_time = min_interval - time_since_last
                self.logger.debug("rate_limit_sleep", seconds=sleep_time)
                time.sleep(sleep_time)

        self.last_request_time = time.time()
        self.requests_made += 1

    def _make_request(self, endpoint: str, params: Dict[str, Any]) -> Dict[str, Any]:
        """Make authenticated request to FRED API."""
        self._rate_limit_check()

        url = f"{self.BASE_URL}/{endpoint}"
        params["api_key"] = self.api_key
        params["file_type"] = "json"

        try:
            response = self.http_session.get(url, params=params, timeout=30)
            response.raise_for_status()

            self.logger.debug("api_request_success", endpoint=endpoint, status=response.status_code)

            return response.json()

        except requests.exceptions.HTTPError as e:
            if e.response.status_code == 429:
                raise RateLimitError(source="FRED", status_code=429, message="Rate limit exceeded")
            raise APIError(source="FRED", status_code=e.response.status_code, message=str(e))
        except requests.exceptions.RequestException as e:
            raise APIError(source="FRED", message=str(e))

    def fetch_series_metadata(self, series_ids: List[str]) -> List[Dict[str, Any]]:
        """Fetch metadata for FRED series."""
        metadata_list = []

        for series_id in series_ids:
            try:
                data = self._make_request("series", {"series_id": series_id})
                series_info = data["seriess"][0]

                metadata = {
                    "source_series_id": series_id,
                    "series_name": series_info.get("title"),
                    "series_description": series_info.get("notes"),
                    "frequency": self._map_frequency(series_info.get("frequency_short")),
                    "units": series_info.get("units"),
                    "seasonal_adjustment": series_info.get("seasonal_adjustment_short"),
                    "geography": "USA",
                }

                metadata_list.append(metadata)

                self.logger.info(
                    "series_metadata_fetched", series_id=series_id, title=metadata["series_name"]
                )

            except APIError as e:
                self.logger.error("series_metadata_fetch_failed", series_id=series_id, error=str(e))
                continue

        return metadata_list

    def fetch_observations(
        self,
        series_id: str,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
    ) -> List[Dict[str, Any]]:
        """Fetch time-series observations for a FRED series."""
        params = {"series_id": series_id}

        if start_date:
            params["observation_start"] = start_date.strftime("%Y-%m-%d")
        if end_date:
            params["observation_end"] = end_date.strftime("%Y-%m-%d")

        try:
            data = self._make_request("series/observations", params)
            observations = data.get("observations", [])

            valid_obs = []
            for obs in observations:
                if obs["value"] != ".":
                    valid_obs.append(
                        {
                            "date": datetime.strptime(obs["date"], "%Y-%m-%d").date(),
                            "value": float(obs["value"]),
                        }
                    )

            self.logger.info(
                "observations_fetched",
                series_id=series_id,
                count=len(valid_obs),
                date_range=(
                    f"{valid_obs[0]['date']} to {valid_obs[-1]['date']}" if valid_obs else "empty"
                ),
            )

            return valid_obs

        except APIError as e:
            self.logger.error("observations_fetch_failed", series_id=series_id, error=str(e))
            return []

    @staticmethod
    def _map_frequency(freq_short: str) -> str:
        """Map FRED frequency codes to standardized codes."""
        mapping = {
            "D": "D",
            "W": "W",
            "BW": "BW",
            "M": "M",
            "Q": "Q",
            "SA": "SA",
            "A": "A",
        }
        return mapping.get(freq_short, freq_short)
