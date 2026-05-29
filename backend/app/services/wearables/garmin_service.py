import time
import hmac
import hashlib
import base64
import urllib.parse
from uuid import uuid4
import httpx
from ...core.config import settings

class GarminAuthService:
    """
    Handles the 3-step OAuth 1.0a dance for Garmin Connect.
    Step 1: Get Request Token
    Step 2: User Authorizes (Flutter opens URL)
    Step 3: Exchange Verifier for Access Token
    """
    
    BASE_URL = "https://connectapi.garmin.com/oauth-service/oauth"
    
    def __init__(self):
        self.consumer_key = settings.GARMIN_CONSUMER_KEY
        self.consumer_secret = settings.GARMIN_CONSUMER_SECRET

    async def get_request_token(self) -> dict:
        """Step 1: Fetch request token and secret."""
        url = f"{self.BASE_URL}/request_token"
        params = self._get_oauth_params()
        params["oauth_callback"] = settings.GARMIN_REDIRECT_URI
        
        signature = self._sign("POST", url, params)
        params["oauth_signature"] = signature
        
        headers = {"Authorization": self._get_auth_header(params)}
        
        async with httpx.AsyncClient() as client:
            resp = await client.post(url, headers=headers)
            resp.raise_for_status()
            
        data = urllib.parse.parse_qs(resp.text)
        return {
            "oauth_token": data["oauth_token"][0],
            "oauth_token_secret": data["oauth_token_secret"][0],
            "authorize_url": f"https://connect.garmin.com/portal/auth?oauth_token={data['oauth_token'][0]}"
        }

    async def get_access_token(self, oauth_token: str, oauth_token_secret: str, oauth_verifier: str) -> dict:
        """Step 3: Exchange request token + verifier for access token."""
        url = f"{self.BASE_URL}/access_token"
        params = self._get_oauth_params(oauth_token)
        params["oauth_verifier"] = oauth_verifier
        
        signature = self._sign("POST", url, params, oauth_token_secret)
        params["oauth_signature"] = signature
        
        headers = {"Authorization": self._get_auth_header(params)}
        
        async with httpx.AsyncClient() as client:
            resp = await client.post(url, headers=headers)
            resp.raise_for_status()
            
        data = urllib.parse.parse_qs(resp.text)
        return {
            "oauth_token": data["oauth_token"][0],
            "oauth_token_secret": data["oauth_token_secret"][0]
        }

    # ── Internal Helpers ─────────────────────────────────────────────────────

    def _get_oauth_params(self, token: str = None) -> dict:
        params = {
            "oauth_consumer_key": self.consumer_key,
            "oauth_nonce": uuid4().hex,
            "oauth_signature_method": "HMAC-SHA1",
            "oauth_timestamp": str(int(time.time())),
            "oauth_version": "1.0",
        }
        if token:
            params["oauth_token"] = token
        return params

    def _sign(self, method: str, url: str, params: dict, token_secret: str = "") -> str:
        # 1. Percent-encode everything
        encoded_params = sorted([(urllib.parse.quote(k, safe=''), urllib.parse.quote(v, safe='')) 
                                for k, v in params.items()])
        param_str = "&".join([f"{k}={v}" for k, v in encoded_params])
        
        # 2. Construct base string
        base_str = "&".join([
            method.upper(),
            urllib.parse.quote(url, safe=''),
            urllib.parse.quote(param_str, safe='')
        ])
        
        # 3. Create signing key
        key = f"{urllib.parse.quote(self.consumer_secret, safe='')}&{urllib.parse.quote(token_secret, safe='')}"
        
        # 4. HMAC-SHA1
        hashed = hmac.new(key.encode(), base_str.encode(), hashlib.sha1)
        return base64.b64encode(hashed.digest()).decode()

    def _get_auth_header(self, params: dict) -> str:
        parts = [f'{urllib.parse.quote(k)}="{urllib.parse.quote(v)}"' for k, v in params.items()]
        return "OAuth " + ", ".join(parts)
