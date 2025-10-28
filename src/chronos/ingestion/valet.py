"""
Project Chronos: Bank of Canada Valet API Ingestion
====================================================
API Documentation: https://www.bankofcanada.ca/valet/docs

Key Differences from FRED:
- No authentication required
- Minimal metadata (no units/seasonal adjustment in API)
- Daily data for most FX rates
- Different JSON structure (dynamic keys)

Version: 2.0 (Fixed frequency extraction)
Last Updated: 2024-10-28
"""

from datetime import datetime
from typing import List, Dict, Any, Optional
import time

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from chronos.ingestion.base import BaseIngestor
from chronos.utils.exceptions import APIError
from chronos.utils.logging import get_logger


class ValetIngestor(BaseIngestor):
    """
    Bank of Canada Valet API ingestor.
    
    Features:
    - Automatic retry with exponential backoff
    - Frequency extraction from API metadata
    - Unit inference from series naming conventions
    - Robust error handling
    """
    
    BASE_URL = "https://www.bankofcanada.ca/valet"
    
    def __init__(self, session):
        super().__init__(session, source_name="VALET")
        self.http_session = self._create_http_session()
        self.logger = get_logger(f"{__name__}.VALET")
        self.requests_made = 0
        self.last_request_time = None
    
    def _create_http_session(self) -> requests.Session:
        """
        Create HTTP session with retry logic.
        
        Returns:
            Configured requests.Session with retry strategy
        """
        session = requests.Session()
        
        # Retry strategy: 3 retries with exponential backoff
        retry_strategy = Retry(
            total=3,
            backoff_factor=1,  # 1s, 2s, 4s
            status_forcelist=[429, 500, 502, 503, 504],
            allowed_methods=["GET"]
        )
        
        adapter = HTTPAdapter(max_retries=retry_strategy)
        session.mount("http://", adapter)
        session.mount("https://", adapter)
        
        return session
    
    def _rate_limit_check(self) -> None:
        """
        Enforce polite rate limiting (no official limit, but be respectful).
        
        Bank of Canada doesn't publish rate limits, so we use conservative 30/min.
        """
        if self.last_request_time is not None:
            time_since_last = time.time() - self.last_request_time
            min_interval = 2.0  # 2 seconds between requests = 30/min
            
            if time_since_last < min_interval:
                sleep_time = min_interval - time_since_last
                self.logger.debug("rate_limit_sleep", seconds=sleep_time)
                time.sleep(sleep_time)
        
        self.last_request_time = time.time()
        self.requests_made += 1
    
    def fetch_series_metadata(self, series_ids: List[str]) -> List[Dict[str, Any]]:
        """
        Fetch metadata for Valet series.
        
        Strategy:
        1. Request recent observation to extract metadata from seriesDetail
        2. Parse frequency from API response
        3. Infer units from series naming conventions
        
        Args:
            series_ids: List of Valet series IDs (e.g., ['FXUSDCAD', 'FXEURCAD'])
            
        Returns:
            List of metadata dictionaries with standardized keys
        """
        metadata_list = []
        
        for series_id in series_ids:
            try:
                self._rate_limit_check()
                
                # Correct URL structure for Valet API
                url = f"{self.BASE_URL}/observations/{series_id}/json"
                
                self.logger.debug(
                    "fetching_metadata",
                    series_id=series_id,
                    url=url
                )
                
                # Fetch recent observation to get metadata
                response = self.http_session.get(
                    url,
                    params={"recent": 1},  # Get 1 recent observation
                    timeout=30
                )
                response.raise_for_status()
                
                data = response.json()
                
                # Extract series details from nested structure
                series_detail = data.get("seriesDetail", {})
                series_info = series_detail.get(series_id, {})
                
                if not series_info:
                    self.logger.warning(
                        "no_series_detail_using_fallback",
                        series_id=series_id,
                        available_keys=list(series_detail.keys()),
                        response_keys=list(data.keys())
                    )
                    # Fallback to minimal metadata
                    series_info = {
                        "label": series_id,
                        "frequency": "daily"  # Default for FX
                    }
                
                # CRITICAL FIX: Extract frequency from API
                raw_frequency = series_info.get("frequency", "daily")
                mapped_frequency = self._map_frequency(raw_frequency)
                
                # Infer units from series ID patterns
                inferred_units = self._infer_units(series_id)
                
                metadata = {
                    "source_series_id": series_id,
                    "series_name": series_info.get("label", series_id),
                    "series_description": series_info.get("description"),
                    "frequency": mapped_frequency,
                    "units": inferred_units,
                    "seasonal_adjustment": None,  # Not provided by Valet API
                    "geography": "CAN",
                }
                
                metadata_list.append(metadata)
                
                self.logger.info(
                    "series_metadata_fetched",
                    series_id=series_id,
                    label=metadata["series_name"],
                    frequency=metadata["frequency"],
                    units=metadata["units"]
                )
                
            except requests.exceptions.HTTPError as e:
                self.logger.error(
                    "series_metadata_fetch_failed",
                    series_id=series_id,
                    status_code=e.response.status_code,
                    error=str(e),
                    url=url,
                    response_text=e.response.text[:500]  # First 500 chars for debugging
                )
                continue
                
            except Exception as e:
                self.logger.error(
                    "series_metadata_unexpected_error",
                    series_id=series_id,
                    error=str(e),
                    error_type=type(e).__name__
                )
                continue
        
        return metadata_list
    
    def fetch_observations(
        self,
        series_id: str,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None
    ) -> List[Dict[str, Any]]:
        """
        Fetch time-series observations from Valet API.
        
        Valet API observations structure:
        {
          "observations": [
            {
              "d": "2024-01-01",           # Date
              "FXUSDCAD": {                # Series-specific key
                "v": "1.3234"              # Value
              }
            }
          ]
        }
        
        Args:
            series_id: Valet series ID
            start_date: Optional start date filter
            end_date: Optional end date filter
            
        Returns:
            List of observation dictionaries with 'date' and 'value' keys
        """
        self._rate_limit_check()
        
        url = f"{self.BASE_URL}/observations/{series_id}/json"
        
        # Valet uses start_date and end_date query params
        params = {}
        if start_date:
            params["start_date"] = start_date.strftime("%Y-%m-%d")
        if end_date:
            params["end_date"] = end_date.strftime("%Y-%m-%d")
        
        try:
            self.logger.debug(
                "fetching_observations",
                series_id=series_id,
                url=url,
                params=params
            )
            
            response = self.http_session.get(url, params=params, timeout=30)
            response.raise_for_status()
            
            data = response.json()
            observations_raw = data.get("observations", [])
            
            if not observations_raw:
                self.logger.warning(
                    "no_observations_returned",
                    series_id=series_id,
                    params=params
                )
                return []
            
            valid_obs = []
            skipped_count = 0
            
            for obs in observations_raw:
                try:
                    # Parse date
                    obs_date = datetime.strptime(obs["d"], "%Y-%m-%d").date()
                    
                    # Extract value - Valet uses dynamic keys
                    # Pattern 1: {series_id: {"v": value}}
                    # Pattern 2: {series_id: value}
                    # Pattern 3: {"v": value}
                    
                    value = None
                    if series_id in obs:
                        series_data = obs[series_id]
                        if isinstance(series_data, dict):
                            value = series_data.get("v")
                        else:
                            value = series_data
                    elif "v" in obs:
                        value = obs["v"]
                    
                    if value is not None:
                        try:
                            valid_obs.append({
                                "date": obs_date,
                                "value": float(value)
                            })
                        except (ValueError, TypeError) as e:
                            self.logger.warning(
                                "invalid_value_conversion",
                                series_id=series_id,
                                date=obs_date,
                                value=value,
                                error=str(e)
                            )
                            skipped_count += 1
                    else:
                        skipped_count += 1
                        
                except (KeyError, ValueError) as e:
                    self.logger.warning(
                        "observation_parse_error",
                        series_id=series_id,
                        observation=obs,
                        error=str(e)
                    )
                    skipped_count += 1
                    continue
            
            self.logger.info(
                "observations_fetched",
                series_id=series_id,
                count=len(valid_obs),
                skipped=skipped_count,
                date_range=f"{valid_obs[0]['date']} to {valid_obs[-1]['date']}" if valid_obs else "empty"
            )
            
            return valid_obs
            
        except requests.exceptions.HTTPError as e:
            self.logger.error(
                "observations_fetch_failed",
                series_id=series_id,
                status_code=e.response.status_code,
                error=str(e),
                response_text=e.response.text[:500]
            )
            return []
            
        except Exception as e:
            self.logger.error(
                "observations_unexpected_error",
                series_id=series_id,
                error=str(e),
                error_type=type(e).__name__
            )
            return []
    
    @staticmethod
    def _map_frequency(freq: str) -> str:
        """
        Map Valet frequency codes to standardized codes.
        
        Valet uses: daily, business, weekly, monthly, quarterly, annual
        
        Args:
            freq: Frequency string from Valet API
            
        Returns:
            Standardized frequency code (D, B, W, M, Q, A)
        """
        if not freq:
            return "D"  # Default to daily for FX rates
        
        mapping = {
            "daily": "D",
            "business": "B",
            "weekly": "W",
            "monthly": "M",
            "quarterly": "Q",
            "annual": "A",
        }
        
        return mapping.get(freq.lower(), "D")
    
    @staticmethod
    def _infer_units(series_id: str) -> Optional[str]:
        """
        Infer units from series ID naming conventions.
        
        Bank of Canada doesn't provide units in API, so we use series ID patterns.
        
        Args:
            series_id: Valet series ID
            
        Returns:
            Inferred unit string or None
        """
        series_upper = series_id.upper()
        
        # FX rates
        if series_upper.startswith("FX"):
            # Extract currency codes
            # FXUSDCAD = CAD per USD
            # FXEURCAD = CAD per EUR
            if len(series_id) >= 8:
                base_currency = series_id[2:5]  # USD, EUR, GBP, etc.
                quote_currency = series_id[5:8]  # Usually CAD
                return f"{quote_currency} per {base_currency}"
            return "Exchange rate"
        
        # Interest rates
        if series_upper.startswith("V12253"):
            return "Percent"
        
        # Policy rates
        if "RATE" in series_upper:
            return "Percent"
        
        # Default
        return None