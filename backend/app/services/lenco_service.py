import requests
import hashlib
import hmac
import logging
from typing import Dict, Any, List, Optional

logger = logging.getLogger("lenco_service")

# Fallback official list of Zambian banks supported by Lenco
DEFAULT_ZAMBIAN_BANKS = [
    {"id": "002", "name": "Absa Bank Zambia", "country": "zm"},
    {"id": "004", "name": "Stanbic Bank Zambia", "country": "zm"},
    {"id": "005", "name": "Standard Chartered Bank Zambia", "country": "zm"},
    {"id": "009", "name": "Zambia National Commercial Bank (Zanaco)", "country": "zm"},
    {"id": "010", "name": "Indo Zambia Bank", "country": "zm"},
    {"id": "014", "name": "First National Bank (FNB Zambia)", "country": "zm"},
    {"id": "016", "name": "Atlas Mara / Access Bank Zambia", "country": "zm"},
    {"id": "018", "name": "Citibank Zambia", "country": "zm"},
    {"id": "022", "name": "Bank of China Zambia", "country": "zm"},
    {"id": "025", "name": "Ecobank Zambia", "country": "zm"},
    {"id": "026", "name": "Investrust Bank", "country": "zm"},
    {"id": "027", "name": "First Alliance Bank", "country": "zm"},
    {"id": "029", "name": "United Bank for Africa (UBA Zambia)", "country": "zm"},
]

class LencoService:
    BASE_URL = "https://api.lenco.co/access/v2"

    @staticmethod
    def _headers(api_key: str) -> Dict[str, str]:
        token = api_key.strip() if api_key else ""
        if token and not token.startswith("Bearer "):
            token = f"Bearer {token}"
        return {
            "Authorization": token,
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 BelekaPOS/1.0",
        }

    @staticmethod
    def _parse_response(resp: requests.Response) -> Dict[str, Any]:
        """Safely parse Lenco API response, handling Cloudflare blocks, auth failures, and non-JSON payloads."""
        try:
            data = resp.json()
            if isinstance(data, dict):
                # If API returned an error payload with status=False or errorCode
                if data.get("status") is False:
                    msg = data.get("message") or "Authentication or validation failed"
                    if "Unauthorized" in msg or resp.status_code == 401 or data.get("errorCode") == "09":
                        msg = "Unauthorized: Invalid or inactive Lenco API Token. Please verify your token in your Lenco Dashboard."
                    data["message"] = msg
                return data
            return {"status": False, "message": "Unexpected response format from Lenco API", "data": data}
        except Exception:
            # HTML or non-JSON returned (e.g. Cloudflare error or 502/503/401/403)
            if resp.status_code == 401:
                return {
                    "status": False,
                    "message": "Unauthorized: Invalid or inactive Lenco API Token. Please verify your token in your Lenco Dashboard.",
                    "data": None,
                }
            elif resp.status_code == 403:
                return {
                    "status": False,
                    "message": "Access Forbidden: Cloudflare or Lenco IP access policy blocked the request.",
                    "data": None,
                }
            elif resp.status_code >= 500:
                return {
                    "status": False,
                    "message": f"Lenco server error (HTTP {resp.status_code}). Please try again later.",
                    "data": None,
                }
            return {
                "status": False,
                "message": f"Invalid response from Lenco (HTTP {resp.status_code}).",
                "data": None,
            }

    @classmethod
    def get_banks(cls, country: str = "zm", api_key: Optional[str] = None) -> List[Dict[str, Any]]:
        """Fetch list of banks from Lenco with fallback to known Zambian banks."""
        if not api_key:
            return DEFAULT_ZAMBIAN_BANKS

        try:
            url = f"{cls.BASE_URL}/banks"
            resp = requests.get(url, params={"country": country}, headers=cls._headers(api_key), timeout=10)
            data = cls._parse_response(resp)
            if data.get("status") and isinstance(data.get("data"), list):
                return data["data"]
            logger.warning(f"Lenco get_banks returned {resp.status_code}: {data.get('message')}")
        except Exception as e:
            logger.error(f"Error fetching banks from Lenco: {e}")

        return DEFAULT_ZAMBIAN_BANKS

    @classmethod
    def resolve_bank_account(
        cls, account_number: str, bank_id: str, country: str = "zm", api_key: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Verify and resolve bank account details to get the account holder's name.
        Endpoint: POST /resolve/bank-account
        """
        if not api_key:
            # Sandbox mock resolution if no key is supplied
            return {
                "status": True,
                "message": "Demo Sandbox Resolution",
                "data": {
                    "type": "bank-account",
                    "accountName": "Jacob Mjuda (Verified Customer)",
                    "accountNumber": account_number,
                    "bank": {
                        "id": bank_id,
                        "name": next((b["name"] for b in DEFAULT_ZAMBIAN_BANKS if b["id"] == bank_id), "Bank of Choice"),
                        "country": country,
                    },
                },
            }

        url = f"{cls.BASE_URL}/resolve/bank-account"
        payload = {
            "accountNumber": account_number.strip(),
            "bankId": bank_id.strip(),
            "country": country,
        }

        try:
            resp = requests.post(url, json=payload, headers=cls._headers(api_key), timeout=15)
            return cls._parse_response(resp)
        except requests.exceptions.Timeout:
            return {"status": False, "message": "Connection to Lenco bank resolver timed out", "data": None}
        except Exception as e:
            logger.error(f"Error resolving bank account with Lenco: {e}")
            return {
                "status": False,
                "message": f"Connection error: {str(e)}",
                "data": None,
            }

    @classmethod
    def resolve_mobile_money(
        cls, phone: str, operator: str, country: str = "zm", api_key: Optional[str] = None
    ) -> Dict[str, Any]:
        """Verify and resolve mobile money phone number."""
        if not api_key:
            return {
                "status": True,
                "message": "Demo Sandbox MoMo Resolution",
                "data": {
                    "accountName": "Verified Mobile Client",
                    "phone": phone,
                    "operator": operator,
                },
            }

        url = f"{cls.BASE_URL}/resolve/mobile-money"
        payload = {
            "phone": phone.strip(),
            "operator": operator.strip().lower(),
            "country": country,
        }
        try:
            resp = requests.post(url, json=payload, headers=cls._headers(api_key), timeout=15)
            return cls._parse_response(resp)
        except requests.exceptions.Timeout:
            return {"status": False, "message": "Connection to Lenco MoMo resolver timed out", "data": None}
        except Exception as e:
            logger.error(f"Error resolving mobile money: {e}")
            return {"status": False, "message": f"Connection error: {str(e)}", "data": None}

    @classmethod
    def get_accounts(cls, api_key: str) -> Dict[str, Any]:
        """Retrieve store merchant accounts and balances on Lenco."""
        if not api_key:
            return {
                "status": False,
                "message": "API Key is required to fetch accounts",
                "data": [],
            }

        url = f"{cls.BASE_URL}/accounts"
        try:
            resp = requests.get(url, headers=cls._headers(api_key), timeout=10)
            data = cls._parse_response(resp)
            if not data.get("status"):
                msg = data.get("message") or "Authentication failed"
                if "Unauthorized" in msg or resp.status_code == 401:
                    msg = "Unauthorized: Invalid or inactive Lenco API Token. Please verify your token in your Lenco Dashboard."
                return {"status": False, "message": msg, "data": []}
            return data
        except requests.exceptions.Timeout:
            return {"status": False, "message": "Connection to Lenco API timed out. Please check your internet connection.", "data": []}
        except Exception as e:
            logger.error(f"Error fetching Lenco accounts: {e}")
            return {"status": False, "message": f"Connection error: {str(e)}", "data": []}

    @classmethod
    def initiate_mobile_money_collection(
        cls,
        amount: float,
        reference: str,
        phone: str,
        operator: str,
        country: str = "zm",
        bearer: str = "merchant",
        api_key: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Request payment from customer mobile money (triggers prompt on phone).
        Endpoint: POST /collections/mobile-money
        """
        if not api_key:
            return {
                "status": True,
                "message": "Demo collection initiated",
                "data": {
                    "reference": reference,
                    "status": "pay-offline",
                    "amount": f"{amount:.2f}",
                    "currency": "ZMW",
                    "mobileMoneyDetails": {
                        "phone": phone,
                        "operator": operator,
                        "country": country,
                    },
                },
            }

        url = f"{cls.BASE_URL}/collections/mobile-money"
        payload = {
            "amount": float(amount),
            "reference": reference,
            "phone": phone.strip(),
            "operator": operator.strip().lower(),
            "country": country,
            "bearer": bearer,
        }

        try:
            resp = requests.post(url, json=payload, headers=cls._headers(api_key), timeout=15)
            return cls._parse_response(resp)
        except requests.exceptions.Timeout:
            return {"status": False, "message": "Connection to Lenco collection service timed out", "data": None}
        except Exception as e:
            logger.error(f"Error initiating mobile money collection: {e}")
            return {"status": False, "message": f"Connection error: {str(e)}", "data": None}

    @classmethod
    def get_collection_status(cls, reference: str, api_key: str) -> Dict[str, Any]:
        """
        Requery collection request status.
        Endpoint: GET /collections/status/{reference}
        """
        if not api_key:
            return {
                "status": True,
                "message": "Sandbox status",
                "data": {
                    "reference": reference,
                    "status": "successful",
                },
            }

        url = f"{cls.BASE_URL}/collections/status/{reference}"
        try:
            resp = requests.get(url, headers=cls._headers(api_key), timeout=10)
            return cls._parse_response(resp)
        except requests.exceptions.Timeout:
            return {"status": False, "message": "Connection to Lenco status service timed out", "data": None}
        except Exception as e:
            logger.error(f"Error querying collection status: {e}")
            return {"status": False, "message": f"Connection error: {str(e)}", "data": None}

    @staticmethod
    def verify_webhook_signature(payload_bytes: bytes, signature_header: str, api_token: str) -> bool:
        """
        Validate HMAC SHA-512 signature using SHA-256 hashed api token.
        webhook_hash_key = SHA256(api_token)
        signature = HMAC_SHA512(payload, webhook_hash_key)
        """
        if not signature_header or not api_token:
            return False

        try:
            webhook_hash_key = hashlib.sha256(api_token.encode("utf-8")).hexdigest()
            expected_sig = hmac.new(
                webhook_hash_key.encode("utf-8"), payload_bytes, hashlib.sha512
            ).hexdigest()
            return hmac.compare_digest(expected_sig.lower(), signature_header.strip().lower())
        except Exception as e:
            logger.error(f"Webhook signature verification failed: {e}")
            return False
