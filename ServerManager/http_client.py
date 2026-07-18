# http_client.py

import requests


class HTTPClient:
    def __init__(self, base_url):
        self.base_url = base_url

    def _make_request(self, endpoint):
        try:
            response = requests.get(f"{self.base_url}{endpoint}")
            response.raise_for_status()  # Raise an exception for HTTP errors (4xx or 5xx)
            return response.json()
        except requests.exceptions.RequestException as e:
            print(f"HTTP Request failed: {e}")
            return None

    def _post_request(self, endpoint):
        try:
            response = requests.post(f"{self.base_url}{endpoint}")
            response.raise_for_status()  # Raise an exception for HTTP errors (4xx or 5xx)
            return response.json()
        except requests.exceptions.RequestException as e:
            print(f"HTTP POST failed: {e}")
            return None

    def get_sessions(self):
        return self._make_request("/sessions")

    def get_ips(self):
        return self._make_request("/ips")

    def get_zones(self):
        return self._make_request("/zones")

    def get_zone_players(self, zone_id):
        return self._make_request(f"/zones/{zone_id}")

    def get_settings(self):
        return self._make_request("/settings")

    def get_campaign_map(self):
        return self._make_request("/campaign/map")

    def get_campaign_nation(self):
        return self._make_request("/campaign/nation")

    def trigger_campaign_refresh(self):
        """Ask the world server to reload campaign state from the DB and
        broadcast it to all map servers. Call this after directly editing
        the campaign_map / campaign_nation tables so map servers pick up
        the change without waiting for the next scheduled tally."""
        return self._post_request("/api/campaign/refresh")
