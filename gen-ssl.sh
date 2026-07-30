#!/usr/bin/env bash
#
# gen-ssl.sh — Generate an internal Root CA (once) + wildcard leaf cert on demand.
# Usage:
#   ./gen-ssl.sh "*.internal.nghia.dev"          # 825-day cert (default)
#   ./gen-ssl.sh "*.internal.nghia.dev" 3650     # custom validity in days
#
# Output layout:
#   ./ca/root-ca.key           <- CA PRIVATE KEY. Guard this like a root password.
#   ./ca/root-ca.crt           <- import this into every device's Trusted Root store
#   ./certs/<domain>/
#       privkey.pem            <- leaf private key (never leaves the server)
#       cert.pem                <- leaf cert only
#       fullchain.pem           <- leaf + CA (use this on nginx/haproxy/etc.)
#       bundle.p12               <- PKCS#12, for Windows/macOS/network device import
#       chain.p7b                <- PKCS#7, some Cisco/F5/Windows tooling wants this instead
#
# NOTE: This is an INTERNAL/PRIVATE CA. It will never be trusted by public
# browsers/clients unless you manually import root-ca.crt into each device's
# trust store. That is by design — do NOT try to pass this off as a publicly
# trusted cert. For public-facing services use Let's Encrypt / ACME instead.

set -euo pipefail

DOMAIN="${1:-}"
DAYS="${2:-825}"          # 825 = Apple's max trusted lifetime, good default habit
CA_DAYS=3650               # 10y root, rotate manually — see note at bottom
KEY_BITS=4096

if [[ -z "$DOMAIN" ]]; then
  echo "Usage: $0 <domain-or-*.wildcard> [validity_days]"
  echo 'Example: $0 "*.internal.nghia.dev" 825'
  exit 1
fi

# --- sanity: openssl present? ---
command -v openssl >/dev/null 2>&1 || { echo "[!] openssl not found. Install it first."; exit 1; }

BASE_DIR="$(pwd)"
CA_DIR="${BASE_DIR}/ca"
CERT_DIR="${BASE_DIR}/certs/${DOMAIN//\*/wildcard}"

mkdir -p "$CA_DIR" "$CERT_DIR"

CA_KEY="${CA_DIR}/root-ca.key"
CA_CRT="${CA_DIR}/root-ca.crt"
CA_SRL="${CA_DIR}/root-ca.srl"

# ---------------------------------------------------------------------------
# Step 1: Bootstrap Root CA — ONLY runs once. If root-ca.key already exists,
# we reuse it. This is intentional: rotating the CA means re-importing it
# into every single device again. Don't regenerate this casually.
# ---------------------------------------------------------------------------
if [[ ! -f "$CA_KEY" ]]; then
  echo "[*] No CA found — bootstrapping a new Root CA (10y validity)..."
  openssl genrsa -out "$CA_KEY" "$KEY_BITS"
  chmod 600 "$CA_KEY"

  openssl req -x509 -new -nodes \
    -key "$CA_KEY" \
    -sha256 \
    -days "$CA_DAYS" \
    -out "$CA_CRT" \
    -subj "/C=VN/O=Nghia-Internal-CA/OU=Infra/CN=Nghia Internal Root CA"

  echo "[+] Root CA created at: $CA_CRT"
  echo "[!] Import THIS FILE into every device's Trusted Root CA store."
else
  echo "[*] Reusing existing Root CA: $CA_CRT"
fi

# ---------------------------------------------------------------------------
# Step 2: Generate leaf key + CSR with proper SAN (modern clients ignore CN,
# they check SAN — skip this and you'll get cert errors on every browser).
# ---------------------------------------------------------------------------
LEAF_KEY="${CERT_DIR}/privkey.pem"
LEAF_CSR="${CERT_DIR}/req.csr"
LEAF_CRT="${CERT_DIR}/cert.pem"
FULLCHAIN="${CERT_DIR}/fullchain.pem"
SAN_CNF="${CERT_DIR}/san.cnf"

# derive apex domain from wildcard (*.foo.com -> foo.com) so both are covered
APEX_DOMAIN="${DOMAIN#\*.}"

cat > "$SAN_CNF" <<EOF
[req]
default_bits       = ${KEY_BITS}
prompt             = no
default_md         = sha256
distinguished_name = dn
req_extensions     = req_ext

[dn]
C  = VN
O  = Nghia-Internal
CN = ${DOMAIN}

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DOMAIN}
DNS.2 = ${APEX_DOMAIN}
EOF

echo "[*] Generating leaf private key + CSR for: ${DOMAIN} (SAN includes ${APEX_DOMAIN})"
openssl genrsa -out "$LEAF_KEY" "$KEY_BITS"
chmod 600 "$LEAF_KEY"

openssl req -new -key "$LEAF_KEY" -out "$LEAF_CSR" -config "$SAN_CNF"

# ---------------------------------------------------------------------------
# Step 3: Sign the CSR with the CA — SAN must be carried over explicitly,
# openssl x509 -req does NOT read req_ext from the CSR by default.
# ---------------------------------------------------------------------------
echo "[*] Signing cert with Root CA (validity: ${DAYS} days)..."
openssl x509 -req \
  -in "$LEAF_CSR" \
  -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial -CAserial "$CA_SRL" \
  -out "$LEAF_CRT" \
  -days "$DAYS" \
  -sha256 \
  -extfile "$SAN_CNF" -extensions req_ext

# ---------------------------------------------------------------------------
# Step 4: Build fullchain + alternate formats for device import.
# ---------------------------------------------------------------------------
cat "$LEAF_CRT" "$CA_CRT" > "$FULLCHAIN"

echo "[*] Building PKCS#12 bundle (for Windows / macOS Keychain / network appliances)..."
openssl pkcs12 -export \
  -inkey "$LEAF_KEY" -in "$LEAF_CRT" -certfile "$CA_CRT" \
  -out "${CERT_DIR}/bundle.p12" \
  -passout pass:changeit   # CHANGE THIS before shipping to prod, see note below

echo "[*] Building PKCS#7 chain (for Cisco/F5/some Windows import wizards)..."
openssl crl2pkcs7 -nocrl -certfile "$FULLCHAIN" -out "${CERT_DIR}/chain.p7b"

# cleanup CSR + cnf, they're not needed post-signing
rm -f "$LEAF_CSR" "$SAN_CNF"

echo ""
echo "======================================================================"
echo " DONE. Files for ${DOMAIN}:"
echo "   Private key   : ${LEAF_KEY}"
echo "   Leaf cert     : ${LEAF_CRT}"
echo "   Full chain    : ${FULLCHAIN}   <- point nginx/haproxy ssl_certificate here"
echo "   PKCS12 bundle : ${CERT_DIR}/bundle.p12   (default password: changeit)"
echo "   PKCS7 chain   : ${CERT_DIR}/chain.p7b"
echo "   CA cert       : ${CA_CRT}   <- import into device trust stores"
echo "======================================================================"
