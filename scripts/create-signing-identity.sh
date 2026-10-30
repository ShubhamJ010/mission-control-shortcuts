#!/bin/bash
# Create the self-signed 'MCSC-Dev' code-signing identity.
#
# Why: macOS ties the Accessibility (TCC) grant to the app's code-signing
# designated requirement. An ad-hoc signature (`-`) uses the cdhash, which
# changes on every build, so each `make install` forces a re-grant. A stable
# certificate makes the requirement "identifier sj010.MCSC and certificate
# leaf = <hash>", which survives rebuilds.
#
# The identity lives in the login keychain and is trusted for code signing in
# the user trust domain, so no admin password is needed.
#
# Idempotent: exits early when the identity already exists.

set -euo pipefail

IDENTITY_NAME="MCSC-Dev"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

if security find-identity -p codesigning -v 2>/dev/null | grep -q "\"${IDENTITY_NAME}\""; then
    echo "==> '${IDENTITY_NAME}' already exists:"
    security find-identity -p codesigning -v | grep "${IDENTITY_NAME}"
    exit 0
fi

echo "==> Generating self-signed '${IDENTITY_NAME}' certificate..."
openssl req -x509 -newkey rsa:2048 \
    -keyout "${WORK_DIR}/key.pem" \
    -out "${WORK_DIR}/cert.pem" \
    -days 3650 -nodes \
    -subj "/CN=${IDENTITY_NAME}/O=MCSC/C=IN" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

# OpenSSL 3 defaults to AES/SHA-256 PKCS#12, which Security.framework rejects
# with "MAC verification failed". -legacy emits the 3DES/SHA-1 flavour it reads.
openssl pkcs12 -export \
    -inkey "${WORK_DIR}/key.pem" \
    -in "${WORK_DIR}/cert.pem" \
    -out "${WORK_DIR}/identity.p12" \
    -name "${IDENTITY_NAME}" \
    -passout pass:mcsc \
    -legacy >/dev/null 2>&1

echo "==> Importing into login keychain..."
security import "${WORK_DIR}/identity.p12" \
    -k "$KEYCHAIN" \
    -P mcsc \
    -T /usr/bin/codesign \
    -T /usr/bin/security >/dev/null

# Without trust settings the certificate imports but `find-identity` reports it
# as invalid, and codesign refuses to use it.
echo "==> Trusting for code signing (user domain)..."
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "${WORK_DIR}/cert.pem"

echo "==> Done:"
security find-identity -p codesigning -v | grep "${IDENTITY_NAME}"
echo
echo "Rebuild with: make install"
echo "The Accessibility grant persists across rebuilds from here on."
