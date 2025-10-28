"""
Project Chronos: Bank of Canada Valet API Ingestion
====================================================
API Docs: https://www.bankofcanada.ca/valet/docs
"""

from datetime import datetime
from typing import List, Dict, Any, Optional
import requests

from chronos.ingestion.base import BaseIngestor
from chronos.utils.exceptions import APIError


class ValetIngestor(BaseIngestor):
    """Bank of Canada Valet API ingestor."""
    
    BASE_URL = "https://www.bankofcanada.ca/valet"
    
    def __init__(self, session):
        super().__init__(session, source_name="VALET")
        self.http_session = requests.Session()
    
    def fetch_series_metadata(self, series_ids: List[str]) -> List[Dict[str, Any]]:
        """Fetch metadata for Valet series."""
        metadata_list = []
        
        for series_id in series_ids:
            try:
                url = f"{self.BASE_URL}/series/{series_id}/observations"
                response = self.http_session.get(url, params={"recent": 1}, timeout=30)
                response.raise_for_status()
                
                data = response.json()
                series_info = data.get("seriesDetail", {}).get(series_id, {})
                
                metadata = {
                    "source_series_id": series_id,
                    "series_name": series_info.get("label"),
                    "series_description": series_info.get("description"),
                    "frequency": series_info.get("frequency"),
                    "units": None,  # Valet doesn't provide units in API
                    "seasonal_adjustment": None,
                    "geography": "CAN",
                }
                
                metadata_list.append(metadata)
                self.logger.info("series_metadata_fetched", series_id=series_id)
                
            except requests.RequestException as e:
                self.logger.error("series_metadata_fetch_failed", series_id=series_id, error=str(e))
                continue
        
        return metadata_list
    
    def fetch_observations(
        self,
        series_id: str,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None
    ) -> List[Dict[str, Any]]:
        """Fetch observations from Valet API."""
        url = f"{self.BASE_URL}/observations/{series_id}/json"
        
        try:
            response = self.http_session.get(url, timeout=30)
            response.raise_for_status()
            
            data = response.json()
            observations = data.get("observations", [])
            
            valid_obs = []
            for obs in observations:
                obs_date = datetime.strptime(obs["d"], "%Y-%m-%d").date()
                
                # Apply date filters
                if start_date and obs_date < start_date.date():
                    continue
                if end_date and obs_date > end_date.date():
                    continue
                
                # Get value (Valet uses dynamic keys like "FXUSDCAD", "v", etc.)
                value = obs.get(series_id) or obs.get("v")
                if value:
                    valid_obs.append({
                        "date": obs_date,
                        "value": float(value)
                    })
            
            self.logger.info("observations_fetched", series_id=series_id, count=len(valid_obs))
            return valid_obs
            
        except requests.RequestException as e:
            self.logger.error("observations_fetch_failed", series_id=series_id, error=str(e))
            return []