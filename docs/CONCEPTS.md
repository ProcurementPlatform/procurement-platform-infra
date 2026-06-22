# Concepts — Viva / Evaluation Prep

Every concept used in this project, with a short "what it is" and **exactly how
it's used here** so you can explain your own work. Grouped by area.

---

## Application & Architecture

**Microservices** — The app is split into 5 independent backend services
(identity, procurement, finance, document, ai) instead of one monolith. Each
owns its own data and can be deployed/scaled independently.
*Why here:* different domains (auth vs finance vs AI) with different scaling
needs; a failure in one doesn't take down the others.

**REST APIs / API Gateway** — Each service exposes HTTP endpoints under `/api`.
A single gateway (Kgateway) routes incoming requests to the right service by URL
path (e.g. `/api/invoices` → finance-service).
*Talking point:* one public entry point, path-based routing, no service exposed
directly to the internet.

**JWT authentication** — On login, identity-service issues a signed JSON Web
Token. Every other service verifies that token using a **shared secret** so a
user logs in once and is trusted across all services (stateless auth — no shared
session store).
*Key detail:* the shared secret must be identical across services — it's stored
once in Secrets Manager and injected into every service.

**RBAC (Role-Based Access Control)** — Each user has a role (admin, finance,
procurement_manager, auditor, vendor, employee); endpoints check the role before
allowing access. The JWT carries the role.

**bcrypt password hashing** — Passwords are stored as bcrypt hashes (12 salt
rounds), never plaintext. Login compares the hash.

---

## Containers & Orchestration

**Docker / multi-stage builds** — Each service is packaged as a container image.
Multi-stage Dockerfiles separate a *build* stage (compiles TypeScript, needs dev
dependencies) from a lean *production* stage (`npm ci --omit=dev`), so the final
image is small and free of build tooling/CVEs. Runs as a non-root user.

**Kubernetes** — The container orchestrator: schedules containers (pods) onto
nodes, restarts them if they crash, scales them, and gives them stable network
identities (Services).

**Amazon EKS (Elastic Kubernetes Service)** — AWS-managed Kubernetes. AWS runs
the control plane; we run a managed node group (2× t3.medium EC2) for workloads.
*Why managed:* no control-plane maintenance, integrates with AWS IAM/VPC.

**Pods / Deployments / Services** — A *Deployment* manages replicas of a *pod*
(running container); a *Service* gives those pods a stable internal DNS name and
load-balances across them.

**HPA (Horizontal Pod Autoscaler)** — Automatically scales the number of pod
replicas based on CPU (min 1, max 10 here). *Note:* we configured ArgoCD to
ignore replica counts so it doesn't fight the HPA.

**Namespaces** — Logical isolation within the cluster: `procurement-prod` (app),
`argocd`, `monitoring`, `kgateway-system`.

---

## GitOps & Deployment

**GitOps** — The desired state of the cluster lives in a Git repo (the gitops
repo's Helm chart). A controller (ArgoCD) continuously makes the cluster match
Git. Deploy = git commit; rollback = git revert.
*Talking point:* Git is the single source of truth and the audit trail.

**ArgoCD** — The GitOps controller. It watches the gitops repo and auto-syncs
changes to the cluster. Self-heals drift (reverts manual changes back to Git).

**Helm** — Kubernetes package manager. Our whole app is one Helm chart with
per-service subcharts; environment differences (dev/prod) come from
`values-dev.yaml` / `values-prod.yaml`.

**Gateway API / Kgateway** — The modern successor to Ingress. A `Gateway`
resource defines the entry point; `HTTPRoute` resources define path→service
routing. Kgateway (Envoy-based) implements it and provisions one NLB for all
services.
*Why over Ingress:* one shared load balancer, cleaner per-service routing,
standard Kubernetes API.

---

## AWS Infrastructure

**Terraform / IaC (Infrastructure as Code)** — All AWS infra is declared in code
and version-controlled. `terraform apply` creates it reproducibly; we can
destroy at night to save cost and recreate identically in the morning.

**Terraform workspaces** — `dev` and `prod` are separate workspaces sharing the
same code but isolated state, so the same modules build both environments.

**Remote state (S3 + DynamoDB lock)** — Terraform state lives in an S3 bucket
with a DynamoDB lock table preventing concurrent applies from corrupting it.

**VPC / subnets / NAT** — Private network: workloads run in private subnets (no
direct internet); a NAT gateway gives them outbound internet; the NLB lives in
public subnets for inbound.

**IRSA (IAM Roles for Service Accounts)** — Each pod assumes a *scoped* AWS IAM
role via the cluster's OIDC provider — e.g. ai-service can call Bedrock,
document-service can read its S3 bucket. **No static AWS keys in the cluster.**
*This is the key security concept — explain it well.*

**OIDC federation for CI/CD** — GitHub Actions authenticates to AWS by exchanging
a short-lived OIDC token for temporary AWS credentials. No long-lived AWS keys
stored in GitHub secrets.

**KMS (Key Management Service)** — Customer-managed encryption keys. DynamoDB,
S3, Secrets Manager, SNS, and CloudWatch logs are all encrypted with KMS.

**Secrets Manager** — Stores per-service runtime config (JWT secret, model IDs,
bucket names). Each service fetches its secret at startup. IAM (via IRSA) scopes
each service to only its own secret path.

**DynamoDB** — Serverless NoSQL database; 15 tables (one per entity) with GSIs
(Global Secondary Indexes) for query patterns like "invoices by status." Chosen
for zero-maintenance and pay-per-use.

**S3** — Object storage for uploaded documents (contracts, invoices, certs).
`force_destroy` is disabled so it won't be wiped by accident.

**ECR (Elastic Container Registry)** — Private Docker registry; the 6 service
images are pushed here by CI and pulled by EKS.

**Route 53 + ACM** — DNS (`procure-flow.online`) and TLS certificates. A wildcard
ACM cert secures the domain; TLS terminates at the NLB.

**Amazon Bedrock** — Managed foundation-model API. ai-service uses **Nova Pro**
for chat/analysis and a Nova embeddings model for document semantic search. No
model hosting — pay per call.

---

## CI/CD

**Pipeline stages (build.yml)** — lint/build → SonarCloud + Snyk scan → semver
tag → build 6 images + Trivy scan → push to ECR → create release tag → email
notify.

**Two-repo deploy pattern** — The app pipeline doesn't deploy directly; it bumps
the image tag in the gitops repo, and ArgoCD does the actual deploy. Clean
separation of "build" and "release."

**Semantic versioning** — On `main`, the tag action computes the next version
from Conventional Commit messages (`feat!:` = major, `feat:` = minor, `fix:` =
patch).

**Branch strategy** — `main ← develop ← feature/*`; PRs gate changes; `main` is
production.

---

## Security Scanning (defense in depth)

| Tool | Scans | Stage |
|---|---|---|
| **tfsec / Checkov** | Terraform misconfigurations | infra CI |
| **SonarCloud** | code quality, bugs, code smells | app CI |
| **Snyk** | vulnerable npm dependencies | app CI |
| **Trivy** | container image CVEs | app CI (per image) |

**NetworkPolicies** — Kubernetes firewall rules. We use **default-deny**: all
pod-to-pod traffic is blocked unless explicitly allowed (Gateway→service,
ai-service→its peers, DNS, AWS APIs). Enforced by the AWS VPC CNI's policy engine.
*Talking point:* zero-trust networking — least privilege at the network layer.

**WAF (Web Application Firewall)** — Filters malicious HTTP traffic (managed rule
sets) at the edge.

---

## Observability

**Prometheus** — Time-series metrics database; scrapes metrics from the cluster
and from each service's `/metrics` endpoint.

**ServiceMonitor** — A CRD telling Prometheus *what* to scrape; we have one per
backend service pointing at its `/metrics`.

**prom-client / RED metrics** — Each service exposes Rate, Errors, Duration
metrics (request count + latency histogram) via shared middleware.

**Grafana** — Dashboards over Prometheus data. We use the built-in Kubernetes
dashboards plus a custom "Procurement Platform — Services" dashboard (per-service
request rate, error rate, p95 latency).

**Alertmanager** — Routes Prometheus alerts to receivers; configured to post to
**Slack** here.

**Two alerting paths:**
1. **App/infra alarms:** CloudWatch alarm → SNS → Lambda → SES email.
2. **Cluster alerts:** Prometheus rule → Alertmanager → Slack.

**CloudWatch** — Central logging: EKS control-plane logs, VPC flow logs,
per-service log groups (KMS-encrypted).

---

## One-line summary to open a viva

> "It's a microservices procurement platform: a React frontend and five Node.js
> services on AWS EKS, deployed via GitOps with ArgoCD, fronted by a Gateway-API
> load balancer. Infrastructure is fully Terraform-managed across dev/prod
> workspaces, secured with IRSA, KMS, NetworkPolicies and OIDC-based CI/CD, and
> observable through Prometheus/Grafana with Slack and email alerting. The AI
> features run on Amazon Bedrock."
