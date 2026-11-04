"""Contoso Orders status page.

Shows whether the infrastructure around the app is wired up. It never changes:
only the environment variables and role assignments set by the infrastructure do.
"""
import os
from html import escape

from azure.core.exceptions import ClientAuthenticationError, HttpResponseError
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.storage.blob import BlobServiceClient
from flask import Flask

app = Flask(__name__)
VERSION = os.environ.get("APP_VERSION", "dev")
SECRET_NAME = "orders-welcome"

_credential = None


def credential():
    global _credential
    if _credential is None:
        _credential = DefaultAzureCredential()
    return _credential


def failure(error):
    if isinstance(error, HttpResponseError) and error.status_code == 403:
        return ("waiting", "Waiting for access", "The managed identity doesn't have a role here yet.")
    if isinstance(error, ClientAuthenticationError):
        return ("error", "Can't sign in", "No managed identity token was available.")
    return ("error", "Error", type(error).__name__)


def check_storage():
    endpoint = os.environ.get("STORAGE_BLOB_ENDPOINT")
    if not endpoint:
        return ("off", "Not set up yet", "STORAGE_BLOB_ENDPOINT is not set.")
    try:
        client = BlobServiceClient(endpoint, credential=credential())
        names = [c.name for c in client.list_containers()]
        return ("ok", "Connected", "Containers: " + (", ".join(names) or "none"))
    except Exception as error:  # surfaced on the page rather than a 500
        return failure(error)


def check_key_vault():
    uri = os.environ.get("KEYVAULT_URI")
    if not uri:
        return ("off", "Not set up yet", "KEYVAULT_URI is not set.")
    try:
        secret = SecretClient(uri, credential()).get_secret(SECRET_NAME)
        return ("ok", "Connected", f"{SECRET_NAME}: {secret.value}")
    except Exception as error:
        return failure(error)


def check_legacy():
    name = os.environ.get("LEGACY_STORAGE_NAME")
    if name:
        return ("warn", "Connected with a shared key", name)
    return ("ok", "Retired", "The legacy storage account is gone.")


PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta http-equiv="refresh" content="10">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Contoso Orders {version}</title>
<style>
  body {{ font-family: Segoe UI, system-ui, sans-serif; background: #f3f2f1; margin: 0; padding: 2rem; color: #201f1e; }}
  main {{ max-width: 44rem; margin: 0 auto; }}
  h1 {{ margin-bottom: 1.5rem; }}
  .card {{ background: #fff; border-left: 8px solid var(--c); border-radius: 4px; padding: 1rem 1.25rem; margin-bottom: 1rem; box-shadow: 0 1px 3px rgba(0,0,0,.12); }}
  .card h2 {{ margin: 0; font-size: 1rem; text-transform: uppercase; letter-spacing: .05em; color: #605e5c; }}
  .card .status {{ font-size: 1.5rem; font-weight: 600; color: var(--c); margin: .25rem 0; }}
  .card .detail {{ color: #605e5c; word-break: break-all; }}
  .ok {{ --c: #107c10; }} .off {{ --c: #8a8886; }} .waiting {{ --c: #d83b01; }}
  .warn {{ --c: #c19c00; }} .error {{ --c: #a4262c; }}
  footer {{ color: #8a8886; font-size: .85rem; }}
</style>
</head>
<body>
<main>
  <h1>Contoso Orders {version}</h1>
  {cards}
  <footer>Refreshes every 10 seconds.</footer>
</main>
</body>
</html>"""

CARD = '<section class="card {state}"><h2>{title}</h2><div class="status">{status}</div><div class="detail">{detail}</div></section>'


@app.route("/")
def index():
    checks = [
        ("Storage", check_storage()),
        ("Key Vault", check_key_vault()),
        ("Legacy storage", check_legacy()),
    ]
    cards = "\n  ".join(
        CARD.format(state=state, title=title, status=escape(status), detail=escape(detail))
        for title, (state, status, detail) in checks
    )
    return PAGE.format(version=escape(VERSION), cards=cards)


@app.route("/healthz")
def healthz():
    return "ok"
