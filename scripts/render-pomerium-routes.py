"""Renders the Pomerium route template with the real tenant list and placeholder secrets, and
prints the routes for a host, so a route edit is read as the YAML Pomerium will load.

Usage: python scripts/render-pomerium-routes.py land.jimr.fyi
"""
import pathlib
import sys

import jinja2
import yaml

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
TEMPLATE = REPO_ROOT / "ansible/roles/pomerium/templates/pomerium-config.yaml.j2"
VARS = REPO_ROOT / "ansible/inventory/group_vars/all/vars.yml"


def render_config():
    variables = yaml.safe_load(VARS.read_text())
    placeholders = {name: "placeholder" for name in (
        "vault_pomerium_cookie_secret", "vault_pomerium_shared_secret",
        "vault_pomerium_db_password", "vault_pomerium_idp_client_id",
        "vault_pomerium_idp_client_secret", "vault_anon_key")}
    environment = jinja2.Environment(undefined=jinja2.StrictUndefined)
    return yaml.safe_load(environment.from_string(TEMPLATE.read_text()).render(**variables, **placeholders))


if __name__ == "__main__":
    host = sys.argv[1]
    for route in render_config()["routes"]:
        if route["from"] == f"https://{host}":
            print(yaml.safe_dump(route, sort_keys=False))
