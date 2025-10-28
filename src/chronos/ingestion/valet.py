"""
Project Chronos: Bank of Canada Valet API Ingestion
====================================================
API Docs: https://www.bankofcanada.ca/valet/docs
Note: Valet API has a simpler structure than FRED - fewer metadata fields
"""

from datetime import datetime
from typing import List, Dict, Any, Optional
import requests

from chronos.ingestion.base import BaseIngestor
from chronos.utils.exceptions import APIError
from chronos.utils.logging import get_logger


class ValetIngestor(BaseIngestor):
    """
    Bank of Canada Valet API ingestor.
    
    API Characteristics:
    - No authentication required
    - No explicit rate limiting (be respectful)
    - Minimal metadata (no units or seasonal adjustment flags)
    - Data returned as JSON with dynamic keys
    """
    
    BASE_URL = "https://www.bankofcanada.ca/valet"
    
    def __init__(self, session):
        super().__init__(session, source_name="VALET")
        self.http_session = requests.Session()
        self.logger = get_logger(f"{__name__}.VALET")
    
    def fetch_series_metadata(self, series_ids: List[str]) -> List[Dict[str, Any]]:
        """
        Fetch metadata for Valet series.
        
        Note: Valet API has limited metadata compared to FRED.
        We extract what we can from the observations endpoint.
        """
        metadata_list = []
        
        for series_id in series_ids:
            try:
                # Correct URL: /observations/{series_id}/json
                url = f"{self.BASE_URL}/observations/{series_id}/json"
                
                self.logger.debug("fetching_metadata", series_id=series_id, url=url)
                
                response = self.http_session.get(url, timeout=30)
                response.raise_for_status()
                
                data = response.json()
                
                # Extract series details (nested in seriesDetail)
                series_detail = data.get("seriesDetail", {})
                series_info = series_detail.get(series_id, {})
                
                if not series_info:
                    self.logger.warning(
                        "no_series_detail",
                        series_id=series_id,
                        available_keys=list(series_detail.keys())
                    )
                    # Fall back to minimal metadata
                    series_info = {"label": series_id}
                
                metadata = {
                    "source_series_id": series_id,
                    "series_name": series_info.get("label", series_id),
                    "series_description": series_info.get("description"),
                    "frequency": self._map_frequency(series_info.get("frequency")),
                    "units": None,  # Valet doesn't provide units in API
                    "seasonal_adjustment": None,  # Not in Valet API
                    "geography": "CAN",
                }
                
                metadata_list.append(metadata)
                
                self.logger.info(
                    "series_metadata_fetched",
                    series_id=series_id,
                    label=metadata["series_name"]
                )
                
            except requests.exceptions.HTTPError as e:
                self.logger.error(
                    "series_metadata_fetch_failed",
                    series_id=series_id,
                    status_code=e.response.status_code,
                    error=str(e),
                    response_text=e.response.text[:200]  # First 200 chars
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
        Fetch observations from Valet API.
        
        Valet returns observations with:
        - "d" key for date
        - Dynamic key matching series_id for value (e.g., "FXUSDCAD": {...})
        - Sometimes nested in the series key, sometimes as "v"
        """
        # Correct URL structure
        url = f"{self.BASE_URL}/observations/{series_id}/json"
        
        # Valet uses start_date and end_date query params
        params = {}
        if start_date:
            params["start_date"] = start_date.strftime("%Y-%m-%d")
        if end_date:
            params["end_date"] = end_date.strftime("%Y-%m-%d")
        
        try:
            self.logger.debug("fetching_observations", series_id=series_id, url=url, params=params)
            
            response = self.http_session.get(url, params=params, timeout=30)
            response.raise_for_status()
            
            data = response.json()
            observations_raw = data.get("observations", [])
            
            valid_obs = []
            for obs in observations_raw:
                # Parse date
                obs_date = datetime.strptime(obs["d"], "%Y-%m-%d").date()
                
                # Get value - Valet uses dynamic keys
                # Try series_id first, then 'v' as fallback
                value = obs.get(series_id, {}).get("v") if isinstance(obs.get(series_id), dict) else obs.get(series_id) or obs.get("v")
                
                if value is not None:
                    try:
                        valid_obs.append({
                            "date": obs_date,
                            "value": float(value)
                        })
                    except (ValueError, TypeError) as e:
                        self.logger.warning(
                            "invalid_value",
                            series_id=series_id,
                            date=obs_date,
                            value=value,
                            error=str(e)
                        )
                        continue
            
            self.logger.info(
                "observations_fetched",
                series_id=series_id,
                count=len(valid_obs),
                date_range=f"{valid_obs[0]['date']} to {valid_obs[-1]['date']}" if valid_obs else "empty"
            )
            
            return valid_obs
            
        except requests.exceptions.HTTPError as e:
            self.logger.error(
                "observations_fetch_failed",
                series_id=series_id,
                status_code=e.response.status_code,
                error=str(e),
                response_text=e.response.text[:200]
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
        """
        if not freq:
            return None
        
        mapping = {
            "daily": "D",
            "business": "B",  # Business days
            "weekly": "W",
            "monthly": "M",
            "quarterly": "Q",
            "annual": "A",
        }
        return mapping.get(freq.lower(), freq)