# Least-privilege policy attached to the "jenkins" AppRole.
# Jenkins can only read the three KV secrets it needs and ask Transit
# to sign/verify with cosign-key — it can never read the private key itself.

path "secret/data/sonarqube" {
  capabilities = ["read"]
}

path "secret/data/dockerhub" {
  capabilities = ["read"]
}

path "secret/data/github" {
  capabilities = ["read"]
}

path "transit/sign/cosign-key" {
  capabilities = ["update"]
}

path "transit/keys/cosign-key" {
  capabilities = ["read"]
}
