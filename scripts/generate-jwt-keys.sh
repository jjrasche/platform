#!/usr/bin/env bash
# Generate ES256 JWT keys and add them to Ansible vault.
# Run from WSL in the platform repo root.
#
# Prerequisites: openssl 3.x, python3, ansible-vault
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
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 \
  -outform PEM -out "$TMPDIR/ec_private.pem" 2>/dev/null

# Extract raw hex from openssl text output
openssl pkey -in "$TMPDIR/ec_private.pem" -text -noout > "$TMPDIR/key_text.txt" 2>/dev/null

echo "Converting to JWK format..."

python3 - "$TMPDIR/key_text.txt" "$JWT_SECRET" > "$TMPDIR/vault_lines.yml" <<'PYEOF'
import sys, json, base64, hashlib, re

def b64url(data):
    if isinstance(data, str):
        data = data.encode()
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()

def b64url_uint(raw_bytes):
    return base64.urlsafe_b64encode(raw_bytes).rstrip(b"=").decode()

key_text_file = sys.argv[1]
jwt_secret = sys.argv[2]

with open(key_text_file) as f:
    text = f.read()

# Parse colon-delimited hex blocks from openssl pkey -text output
# Format: "priv:\n    xx:xx:...\npub:\n    04:xx:xx:..."
sections = re.split(r'\n(priv|pub):\s*\n', text)

hex_blocks = {}
for i, section in enumerate(sections):
    if section in ('priv', 'pub') and i + 1 < len(sections):
        hex_str = sections[i + 1].split('\n')
        hex_str = ''.join(line.strip() for line in hex_str
                         if ':' in line or (line.strip() and not line.strip().startswith(('ASN', 'NIST', 'Private'))))
        hex_str = hex_str.replace(':', '')
        hex_blocks[section] = hex_str

priv_hex = hex_blocks['priv']
pub_hex = hex_blocks['pub']

d_bytes = bytes.fromhex(priv_hex)[-32:].rjust(32, b"\x00")

# Remove 04 prefix (uncompressed point)
if pub_hex.startswith("04"):
    pub_hex = pub_hex[2:]
x_bytes = bytes.fromhex(pub_hex[:64])
y_bytes = bytes.fromhex(pub_hex[64:128])

kid = hashlib.sha256(x_bytes + y_bytes).hexdigest()[:16]

private_jwk = {
    "kty": "EC", "crv": "P-256", "kid": kid, "key_ops": ["sign"], "alg": "ES256",
    "x": b64url_uint(x_bytes), "y": b64url_uint(y_bytes), "d": b64url_uint(d_bytes),
}
public_jwk = {k: v for k, v in private_jwk.items() if k != "d"}
hs256_jwk = {"kty": "oct", "k": b64url(jwt_secret), "kid": "legacy-hs256", "use": "sig", "alg": "HS256"}

# GoTrue expects a bare JSON array, not {"keys": [...]}
gotrue_jwt_keys = json.dumps([private_jwk], separators=(",", ":"))
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
