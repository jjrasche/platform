#!/usr/bin/env python3
"""Fix GOTRUE_JWT_KEYS: add key_ops field for signing detection."""
import sys, json, re

vault_file = sys.argv[1]

with open(vault_file) as f:
    content = f.read()

match = re.search(r"vault_gotrue_jwt_keys: '(.*?)'", content)
if not match:
    print("vault_gotrue_jwt_keys not found")
    sys.exit(1)

current = match.group(1)
parsed = json.loads(current)

# Unwrap {"keys": [...]} if needed
if isinstance(parsed, dict) and "keys" in parsed:
    parsed = parsed["keys"]

changed = False
for key in parsed:
    # Remove "use" field, add "key_ops" for GoTrue's signing key detection
    if "use" in key:
        del key["use"]
        changed = True
    if "key_ops" not in key:
        key["key_ops"] = ["sign"]
        changed = True

if changed:
    fixed = json.dumps(parsed, separators=(",", ":"))
    content = content.replace(
        f"vault_gotrue_jwt_keys: '{current}'",
        f"vault_gotrue_jwt_keys: '{fixed}'"
    )
    with open(vault_file, "w") as f:
        f.write(content)
    print(f"Fixed: added key_ops to signing key")
else:
    print("Already correct")
