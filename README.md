# 🔐 Spring Boot DevSecOps Pipeline — Jenkins · SonarQube · Argo CD

A production-style **DevSecOps** CI/CD pipeline for a Java 17 Spring Boot application, deployed on a Kubernetes cluster provisioned on AWS EC2. Security is embedded at every stage — from code commit to production rollout: shift-left SAST and image/filesystem scanning (Trivy), supply-chain integrity via SBOM generation and scanning (Syft/Grype) and image signing (Cosign), policy-as-code admission control (Kyverno), and dynamic secrets issued at build time by HashiCorp Vault instead of long-lived static credentials.

> **Collaboration:** Pipeline architecture and GitOps delivery by **Omar Chouchane** · DevSecOps layer (SonarQube reporting & quality gate enforcement) by **Houssem Bouarada**

---

## 🏗️ Architecture

<img width="4399" height="1951" alt="JENKINS END TO END CICD PIPELINE (1)" src="https://github.com/user-attachments/assets/4ad17a8a-df0f-411e-a316-fb114689ae7a" />

---

## 🔄 Pipeline Flow (Shift-Left Security)

```
Code Commit
    │
    ▼
1. Checkout source from GitHub
    │
    ▼
2. Fetch dynamic secrets — Jenkins authenticates to Vault via AppRole,
   gets a short-lived token, reads SonarQube/DockerHub/GitHub secrets
    │
    ▼
3. Build & Test — Maven (deterministic, reproducible builds)
    │
    ▼
4. 🔍 SAST — SonarQube analysis + Quality Gate enforcement
    │   └─ Fail-fast: pipeline halts if gate fails
    ▼
5. Trivy filesystem scan — source & dependency CVEs (shift-left)
    │
    ▼
6. Build Docker image (immutable artifact)
    │
    ▼
7. Trivy image scan — fails build on CRITICAL image vulnerabilities
    │
    ▼
8. Push to Docker Hub → omarchouchane/ultimate-cicd:<build_number>
    │
    ▼
9. Generate SBOM (Syft, CycloneDX) → archived as a build artifact
    │
    ▼
10. Scan SBOM for vulnerabilities (Grype) — fails build on CRITICAL
    │
    ▼
11. Sign image (Cosign) — signing key held in Vault's Transit engine,
    private key material never leaves Vault
    │
    ▼
12. GitOps — Clone manifests repo, update image tag, push to main
    │
    ▼
13. Argo CD detects drift → reconciles desired vs. actual state → deploys
    │
    ▼
14. Kyverno admission controller verifies the Cosign signature against
    the Vault Transit key before the Pod is allowed to run
```

---

## 🛡️ DevSecOps Layers

### Static Application Security Testing (SAST)
- **SonarQube 10.x** integrated into the CI pipeline as a central policy enforcement point
- Scans for vulnerabilities, code smells, and security hotspots on every commit
- Quality Gate blocks downstream stages (Docker push, deployment update) on failure
- Audit-ready reports generated within the pipeline for compliance traceability
- Aligns with **Secure SDLC** and compliance-driven delivery practices

### Shift-Left Security
- Security checks run *before* containerization — vulnerabilities caught at the source, not in production
- `sonar.qualitygate.wait=true` ensures the pipeline halts synchronously on non-compliant results
- Fail-fast mechanism: no artifact is built or deployed from a codebase that fails the security gate

### Immutable Artifacts
- Docker images tagged by Jenkins build number — no mutable `latest` tags in delivery
- Images pushed to Docker Hub only after passing the Quality Gate

### GitOps & Auditability
- Kubernetes manifests versioned in a **separate repository** — full change history and auditability
- Argo CD enforces desired-state reconciliation, preventing configuration drift
- All deployments are declarative and traceable via Git commits

### Supply-Chain Integrity
- **SBOM generation (Syft):** every image gets a CycloneDX SBOM, archived as a build artifact for provenance and audit
- **SBOM vulnerability scanning (Grype):** the SBOM is scanned for known CVEs; build fails on CRITICAL findings
- **Image signing (Cosign):** every pushed image is signed using a key managed entirely inside Vault's **Transit** secrets engine (`hashivault://cosign-key`) — the private key is never written to disk or exposed to Jenkins, Vault performs the signing operation itself

### Vulnerability Scanning (Trivy)
- **Filesystem scan** runs before the image is even built — catches vulnerable dependencies at the source (shift-left)
- **Image scan** runs against the built Docker image before it's pushed — catches OS/package-level CVEs
- Both fail the pipeline on CRITICAL/HIGH findings, same fail-fast philosophy as the SonarQube gate

### Policy-as-Code Admission Control (Kyverno)
- A `ClusterPolicy` ([kyverno/require-signed-images.yaml](kyverno/require-signed-images.yaml)) enforces `verifyImages` on every Pod using `omarchouchane/ultimate-cicd:*`
- Verification is done against the same Vault Transit key used to sign — no separate public key material to manage or rotate manually
- Unsigned or tampered images are rejected at admission time, independent of what Jenkins already checked — a second, cluster-side enforcement boundary

### Dynamic Secrets Management (HashiCorp Vault)
- Jenkins holds exactly **one** long-lived credential: an AppRole `role_id`/`secret_id` pair
- At the start of each build, Jenkins authenticates to Vault via AppRole and receives a **short-lived token** (15m TTL), used only for that pipeline run and revoked in the `post` block when the build finishes
- SonarQube token, Docker Hub credentials, and GitHub token are read from Vault's KV v2 engine at runtime — never stored as static Jenkins credentials
- The Cosign signing key lives in Vault's Transit engine — Jenkins can request a *signature*, never the key itself
- See [vault/setup.sh](vault/setup.sh) and [vault/jenkins-policy.hcl](vault/jenkins-policy.hcl) for the bootstrap configuration

---

## 🧰 Tech Stack

| Layer | Tools |
|---|---|
| Language & Runtime | Java 17, Spring Boot |
| Build | Maven 3.9+ |
| CI Orchestration | Jenkins (Pipeline as Code) |
| SAST & Quality Gate | SonarQube 10.x |
| Vulnerability Scanning | Trivy (filesystem + image) |
| Containerization | Docker |
| Container Registry | Docker Hub |
| SBOM | Syft (generation), Grype (SBOM scanning) |
| Supply-Chain Integrity | Cosign (image signing) |
| Policy-as-Code / Admission Control | Kyverno |
| Secrets Management | HashiCorp Vault (AppRole, KV v2, Transit) |
| GitOps CD | Argo CD |
| Orchestration | Kubernetes (AWS EC2) |

---

## 📁 Repository Structure

```
.
├── Jenkinsfile              # Pipeline as Code
├── Dockerfile
├── pom.xml
├── argocd-basic.yml
├── kyverno/
│   └── require-signed-images.yaml   # Admission control: enforce signed images
├── vault/
│   ├── setup.sh                     # AppRole / KV / Transit bootstrap
│   └── jenkins-policy.hcl           # Least-privilege policy for Jenkins' AppRole
└── src/
    └── main/
        ├── java/com/abhishek/StartApplication.java
        └── resources/
```

**Separate manifests repo:** [spring-app-manifests](https://github.com/OmarChouchane/spring-app-manifests)

---

## ⚙️ Prerequisites

- JDK 17
- Maven 3.9+
- Docker
- Kubernetes cluster (`kubectl` configured)
- Jenkins server
- SonarQube server
- Argo CD installed on cluster
- HashiCorp Vault server (AppRole auth, KV v2, and Transit engines enabled — see [vault/setup.sh](vault/setup.sh))
- Kyverno installed on cluster

---

## 🚀 Run Locally

```bash
# Build
mvn clean package

# Run
java -jar target/spring-boot-web.jar
```

Open: `http://localhost:8080`

---

## 🐳 Run with Docker

```bash
docker build -t omarchouchane/ultimate-cicd:local .
docker run -d -p 8080:8080 --name spring-boot-app omarchouchane/ultimate-cicd:local
```

---

## 🔧 Jenkins Setup

**Required credentials:**

| ID | Type | Purpose |
|---|---|---|
| `vault-approle` | Username/password (username=`role_id`, password=`secret_id`) | Only credential Jenkins holds — used to fetch every other secret from Vault at build time |

All other secrets (SonarQube token, Docker Hub credentials, GitHub token, Cosign signing key) live in Vault, not in Jenkins. See [Dynamic Secrets Management](#dynamic-secrets-management-hashicorp-vault) above and [vault/setup.sh](vault/setup.sh) to bootstrap them.

**Recommended trigger:**
- Build Trigger: `GitHub hook trigger for GITScm polling`
- Webhook URL: `http://<jenkins-public-ip>:8080/github-webhook/`

---

## 🔍 SonarQube Quality Gate

The pipeline waits synchronously for the Quality Gate result:

```properties
sonar.qualitygate.wait=true
sonar.qualitygate.timeout=300
```

**If the Quality Gate fails:**
- Docker image build is skipped
- Docker Hub push is skipped
- Manifest update and Argo CD sync are skipped
- Pipeline exits with a non-zero status for full traceability

> This is the fail-fast security enforcement layer contributed by **Houssem Bouarada**, including enhanced SonarQube reporting and fail-on-quality/security-test logic.

---

## 🔁 Argo CD Setup

```bash
kubectl apply -f argocd-basic.yml
```

**Application source values:**

| Field | Value |
|---|---|
| Repository URL | `https://github.com/OmarChouchane/spring-app-manifests` |
| Revision | `main` |
| Path | `.` |
| Namespace | `default` |

---

## 🛂 Kyverno Setup

Install Kyverno on the cluster, then apply the admission policy:

```bash
kubectl create -f https://github.com/kyverno/kyverno/releases/latest/download/install.yaml
kubectl apply -f kyverno/require-signed-images.yaml
```

Kyverno verifies image signatures against the same `hashivault://cosign-key` used in the pipeline's Cosign stage — no public key files to distribute or rotate manually. Kyverno's Vault access requires `VAULT_ADDR`/`VAULT_TOKEN` (or Kubernetes auth) configured on its controller; see the [Kyverno KMS docs](https://kyverno.io/docs/writing-policies/verify-images/) for cluster-side Vault wiring.

---

## 🔑 Vault Setup

```bash
export VAULT_ADDR=http://<vault-host>:8200
vault login   # operator token

cd vault
./setup.sh
```

This enables the `kv-v2`, `transit`, and `approle` engines, creates the `cosign-key` Transit key, writes the `jenkins-policy`, and creates the `jenkins` AppRole. Take the printed `role_id`/`secret_id` and store them as the single `vault-approle` Jenkins credential.

---

## 🩺 Troubleshooting

```bash
# Jenkins status
sudo systemctl status jenkins --no-pager

# SonarQube port
sudo netstat -tlnp | grep 9000

# Disk space
df -h
```

**Webhook not triggering?**
- Verify EC2 inbound rule allows port `8080`
- Check Jenkins URL setting under Manage Jenkins → System
- Verify GitHub webhook delivery shows HTTP `200`

---

## 🔒 Security Notes

- **Never commit hardcoded credentials** to any branch
- Jenkins holds a single AppRole credential; every other secret is issued dynamically by Vault at build time and the build token is revoked when the pipeline finishes
- The Cosign private key never exists outside Vault's Transit engine — Jenkins can only request signatures, never key material
- Test vulnerability scenarios on isolated branches only — revert immediately after validating pipeline behavior
- SonarQube Quality Gate, Trivy scans, and Grype SBOM scans are all fail-fast enforcement boundaries: no non-compliant code or vulnerable image reaches the container registry
- Kyverno is a second, cluster-side enforcement boundary independent of Jenkins — even a compromised Jenkins can't get an unsigned image running in the cluster

---

## 📄 License

This project is for learning and demonstration purposes. Add a formal license file if deploying to production.
