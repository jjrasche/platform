#!/usr/bin/env bash
# Generate ES256 JWT keys and add them to Ansible vault.
# Run from WSL in the platform repo root.
#
# Prerequisites: openssl, python3, ansible-vault
# Usage: ./scripts/generate-jwt-keys.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VAULT_FILE="$REPO_ROOT/ansible/inventory/group_vars/all/vault.yml"
VAULT_PASS_FILE="${VAULT_PASS_FILE:-/home/jrasche/.vault_pass}"

if [ ! -f "$VAULT_FILE" ]; then
  echo "ERROR: vault.yml not found at $VAULT_FILE"
  exit 1
fi

if [ ! -f "$VAULT_PASS_FILE" ]; then
  echo "ERROR: vault password file not found at $VAULT_PASS_FILE"
  echo "  Set VAULT_PASS_FILE env var if it's elsewhere"
  exit 1
fi

# Read current JWT_SECRET from vault
JWT_SECRET=$(ansible-vault view "$VAULT_FILE" --vault-password-file "$VAULT_PASS_FILE" \
  | grep '^vault_jwt_secret:' | sed 's/vault_jwt_secret: *//')

if [ -z "$JWT_SECRET" ]; then
  echo "ERROR: could not read vault_jwt_secret from vault"
  exit 1
fi

echo "Read JWT_SECRET from vault."

# Check if keys already exist
if ansible-vault view "$VAULT_FILE" --vault-password-file "$VAULT_PASS_FILE" \
  | grep -q '^vault_gotrue_jwt_keys:'; then
  echo "ERROR: vault_gotrue_jwt_keys already exists in vault."
  echo "  Remove it first if you want to regenerate."
  exit 1
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Generating EC P-256 key pair..."
openssl ecparam -genkey -name prime256v1 -noout -out "$TMPDIR/ec_private.pem" 2>/dev/null
openssl ec -in "$TMPDIR/ec_private.pem" -pubout -out "$TMPDIR/ec_public.pem" 2>/dev/null

echo "Converting to JWK format..."

python3 - "$TMPDIR/ec_private.pem" "$JWT_SECRET" > "$TMPDIR/vault_lines.yml" <<'PYEOF'
import sys, json, base64, hashlib, subprocess

def b64url(data):
    if isinstance(data, str):
        data = data.encode()
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()

def b64url_uint(num_bytes):
    return base64.urlsafe_b64encode(num_bytes).rstrip(b"=").decode()

private_pem = sys.argv[1]
jwt_secret = sys.argv[2]

# Extract EC key components via openssl
result = subprocess.run(
    ["openssl", "ec", "-in", private_pem, "-text", "-noout"],
    capture_output=True, text=True
)
lines = result.stdout.replace(" ", "").replace(":", "").replace("\n", "")

priv_start = lines.index("priv:") + 5
pub_start = lines.index("pub:")
priv_hex = lines[priv_start:pub_start]
d_bytes = bytes.fromhex(priv_hex)[-32:].rjust(32, b"\x00")

pub_hex = lines[pub_start + 4:]
if pub_hex.startswith("04"):
    pub_hex = pub_hex[2:]
x_bytes = bytes.fromhex(pub_hex[:64])
y_bytes = bytes.fromhex(pub_hex[64:128])

kid = hashlib.sha256(x_bytes + y_bytes).hexdigest()[:16]

private_jwk = {
    "kty": "EC", "crv": "P-256", "kid": kid, "use": "sig", "alg": "ES256",
    "x": b64url_uint(x_bytes), "y": b64url_uint(y_bytes), "d": b64url_uint(d_bytes),
}
public_jwk = {k: v for k, v in private_jwk.items() if k != "d"}
hs256_jwk = {"kty": "oct", "k": b64url(jwt_secret), "kid": "legacy-hs256", "use": "sig", "alg": "HS256"}

gotrue_jwt_keys = json.dumps({"keys": [private_jwk]}, separators=(",", ":"))
jwt_jwks = json.dumps({"keys": [public_jwk, hs256_jwk]}, separators=(",", ":"))

print(f"vault_gotrue_jwt_keys: '{gotrue_jwt_keys}'")
print(f"vault_jwt_jwks: '{jwt_jwks}'")
PYEOF

echo "Adding keys to vault..."

# Decrypt, append, re-encrypt
ansible-vault decrypt "$VAULT_FILE" --vault-password-file "$VAULT_PASS_FILE"
echo "" >> "$VAULT_FILE"
echo "# Asymmetric JWT keys for OAuth 2.1 Server (ES256)" >> "$VAULT_FILE"
cat "$TMPDIR/vault_lines.yml" >> "$VAULT_FILE"
ansible-vault encrypt "$VAULT_FILE" --vault-password-file "$VAULT_PASS_FILE"

echo ""
echo "Done. Keys added to vault. Existing HS256 tokens remain valid."
echo "Deploy with: cd ansible && ansible-playbook -i inventory playbook.yml"
