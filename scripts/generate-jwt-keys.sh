#!/usr/bin/env bash
# Generate asymmetric JWT keys for Supabase OAuth 2.1 Server.
# Run this once, then add the output values to ansible vault.
#
# Prerequisites: openssl, python3
# Usage: ./scripts/generate-jwt-keys.sh <current-jwt-secret>

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <current-jwt-secret>"
  echo "  Get current JWT_SECRET from: ansible-vault view ansible/inventory/group_vars/all/vault.yml"
  exit 1
fi

JWT_SECRET="$1"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Generating EC P-256 key pair..."
openssl ecparam -genkey -name prime256v1 -noout -out "$TMPDIR/ec_private.pem" 2>/dev/null
openssl ec -in "$TMPDIR/ec_private.pem" -pubout -out "$TMPDIR/ec_public.pem" 2>/dev/null

echo "Converting to JWK format..."

python3 - "$TMPDIR/ec_private.pem" "$TMPDIR/ec_public.pem" "$JWT_SECRET" <<'PYEOF'
import sys, json, base64, hashlib

def b64url(data):
    if isinstance(data, str):
        data = data.encode()
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()

def b64url_uint(num_bytes):
    return base64.urlsafe_b64encode(num_bytes).rstrip(b"=").decode()

def pem_to_ec_jwk(private_pem, public_pem):
    """Extract EC key components from PEM using openssl output parsing."""
    import subprocess
    result = subprocess.run(
        ["openssl", "ec", "-in", private_pem, "-text", "-noout"],
        capture_output=True, text=True
    )
    lines = result.stdout.replace(" ", "").replace(":", "").replace("\n", "")

    # Parse the private key value (after "priv:")
    priv_start = lines.index("priv:") + 5
    pub_start = lines.index("pub:")
    priv_hex = lines[priv_start:pub_start]
    d_bytes = bytes.fromhex(priv_hex)
    # Ensure 32 bytes (pad or trim leading zero)
    d_bytes = d_bytes[-32:].rjust(32, b"\x00")

    pub_hex = lines[pub_start + 4:]
    # Remove the 04 prefix (uncompressed point indicator)
    if pub_hex.startswith("04"):
        pub_hex = pub_hex[2:]
    x_bytes = bytes.fromhex(pub_hex[:64])
    y_bytes = bytes.fromhex(pub_hex[64:128])

    kid = hashlib.sha256(x_bytes + y_bytes).hexdigest()[:16]

    private_jwk = {
        "kty": "EC",
        "crv": "P-256",
        "kid": kid,
        "use": "sig",
        "alg": "ES256",
        "x": b64url_uint(x_bytes),
        "y": b64url_uint(y_bytes),
        "d": b64url_uint(d_bytes),
    }
    public_jwk = {k: v for k, v in private_jwk.items() if k != "d"}
    return private_jwk, public_jwk, kid

def jwt_secret_to_jwk(secret):
    """Wrap HS256 secret as a JWK for backward compatibility."""
    return {
        "kty": "oct",
        "k": b64url(secret),
        "kid": "legacy-hs256",
        "use": "sig",
        "alg": "HS256",
    }

private_pem = sys.argv[1]
public_pem = sys.argv[2]
jwt_secret = sys.argv[3]

private_jwk, public_jwk, kid = pem_to_ec_jwk(private_pem, public_pem)
hs256_jwk = jwt_secret_to_jwk(jwt_secret)

# GOTRUE_JWT_KEYS: private key for GoTrue to sign tokens
gotrue_jwt_keys = json.dumps({"keys": [private_jwk]}, separators=(",", ":"))

# JWT_JWKS: public key + legacy HS256 for verification services
jwt_jwks = json.dumps({"keys": [public_jwk, hs256_jwk]}, separators=(",", ":"))

print()
print("=" * 60)
print("Add these to ansible vault (vault.yml):")
print("=" * 60)
print()
print(f"vault_gotrue_jwt_keys: '{gotrue_jwt_keys}'")
print()
print(f"vault_jwt_jwks: '{jwt_jwks}'")
print()
print("=" * 60)
print("IMPORTANT: After deploying with these keys, existing")
print("HS256 tokens remain valid (JWT_JWKS includes the legacy key).")
print("New tokens will be signed with ES256.")
print()
print("You must also re-sign ANON_KEY and SERVICE_ROLE_KEY")
print("with the new ES256 key. Use the Supabase key generation")
print("utility or jwt.io to create new keys with these claims:")
print()
print("  ANON_KEY:  {\"role\": \"anon\", \"iss\": \"supabase\"}")
print("  SERVICE:   {\"role\": \"service_role\", \"iss\": \"supabase\"}")
print("=" * 60)
PYEOF

echo ""
echo "Done. See output above for vault values."
