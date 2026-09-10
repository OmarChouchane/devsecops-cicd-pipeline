#!/usr/bin/env bash
# One-time Vault bootstrap for this pipeline.
# Run against a dev/prod Vault server with an operator token that has admin rights.
set -euo pipefail

# --- KV v2 engine for static-but-centrally-managed secrets ---
vault secrets enable -path=secret kv-v2 || true

vault kv put secret/sonarqube token="<sonarqube-token>"
vault kv put secret/dockerhub username="<dockerhub-username>" password="<dockerhub-password-or-pat>"
vault kv put secret/github token="<github-pat>"

# --- Transit engine for Cosign signing key (private key never leaves Vault) ---
vault secrets enable transit || true
vault write -f transit/keys/cosign-key type=ecdsa-p256

# --- AppRole auth so Jenkins gets a short-lived token per build ---
vault auth enable approle || true
vault policy write jenkins-policy jenkins-policy.hcl
vault write auth/approle/role/jenkins \
  token_policies="jenkins-policy" \
  token_ttl=15m \
  token_max_ttl=30m

# Retrieve credentials to store as a single Jenkins "Username with password"
# credential (id: vault-approle) -> username=role_id, password=secret_id
vault read auth/approle/role/jenkins/role-id
vault write -f auth/approle/role/jenkins/secret-id
