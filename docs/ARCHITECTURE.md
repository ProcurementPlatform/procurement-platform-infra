# Procurement Platform — Architecture

A cloud-native procurement management platform: a React SPA + 5 Node.js
microservices, deployed on AWS EKS via GitOps, with AI features powered by
Amazon Bedrock. Split across **3 repositories**:

| Repo | Holds |
|---|---|
| `procurement-platform-app` | Application source (frontend + 5 services), Dockerfiles, build/deploy CI/CD |
| `procurement-platform-infra` | Terraform (AWS infra), cluster bootstrap + secret scripts |
| `procurement-platform-gitops` | Helm chart + ArgoCD Application manifests (desired cluster state) |

> Render the Mermaid diagrams below at https://mermaid.live or with the VS Code
> "Markdown Preview Mermaid" extension to export images for slides.

---

## 1. Application Architecture

Six containers behind a single API gateway. Each service owns its own data
(DynamoDB tables) and exposes a REST API under `/api`. Only the AI service calls
other services; everyone else is independent.

```mermaid
graph TD
    User([User / Browser]) -->|HTTPS| GW[Kgateway / Envoy<br/>API Gateway]

    GW -->|/| FE[frontend<br/>React SPA + nginx]
    GW -->|/api/auth, /api/users| ID[identity-service<br/>:5001]
    GW -->|/api/vendors, /api/contracts,<br/>/api/purchase-*| PR[procurement-service<br/>:5003]
    GW -->|/api/invoices, /api/payments,<br/>/api/customers| FIN[finance-service<br/>:5002]
    GW -->|/api/documents, /api/audit,<br/>/api/notifications| DOC[document-service<br/>:5004]
    GW -->|/api/ai| AI[ai-service<br/>:5006]

    AI -.->|profile / RBAC| ID
    AI -.->|invoices, payments| FIN
    AI -.->|vendors, POs, contracts| PR
    AI -.->|documents| DOC

    ID --> DDB[(DynamoDB<br/>15 tables)]
    PR --> DDB
    FIN --> DDB
    DOC --> DDB
    AI --> DDB

    DOC --> S3[(S3<br/>documents)]
    AI -->|chat, embeddings,<br/>risk analysis| BR[Amazon Bedrock<br/>Nova Pro / Nova Embeddings]

    classDef svc fill:#2563eb,color:#fff,stroke:#1e40af
    classDef data fill:#059669,color:#fff,stroke:#047857
    class ID,PR,FIN,DOC,AI,FE svc
    class DDB,S3,BR data
```

**Services:**
- **identity-service** — auth (bcrypt + JWT), users. Signs the JWT every other service verifies.
- **procurement-service** — vendors, contracts, purchase requests, purchase orders.
- **finance-service** — invoices (GST/TDS), payments, customers.
- **document-service** — document upload/download (S3), audit logs, notifications.
- **ai-service** — Procurement Copilot (chat), contract intelligence, invoice risk analysis, document semantic search. Aggregates data from the other 4 services over REST and reasons over it with Bedrock.
- **frontend** — React SPA served by nginx; all API calls go through the gateway at `/api`.

**Auth flow:** identity-service signs a JWT with a shared secret (from Secrets
Manager); every service verifies it with the same secret via shared middleware.
RBAC roles: `admin`, `procurement_manager`, `finance`, `auditor`, `vendor`, `employee`.

---

## 2. AWS Infrastructure Architecture

```mermaid
graph TB
    subgraph Internet
        U([Users])
        GH[GitHub Actions<br/>CI/CD]
    end

    subgraph AWS["AWS Account (us-east-1)"]
        R53[Route 53<br/>procure-flow.online]
        ACM[ACM<br/>wildcard TLS cert]

        subgraph VPC["VPC (2 AZs)"]
            subgraph Public["Public subnets"]
                NLB[NLB<br/>internet-facing]
                NAT[NAT Gateways]
            end
            subgraph Private["Private subnets"]
                subgraph EKS["EKS Cluster"]
                    NODES[Managed Node Group<br/>t3.medium x2]
                    subgraph NS["namespaces"]
                        APPNS[procurement-prod<br/>6 services + Kgateway]
                        ARGONS[argocd]
                        MONNS[monitoring<br/>Prometheus/Grafana]
                    end
                end
            end
        end

        ECR[ECR<br/>6 image repos]
        DDB[(DynamoDB<br/>15 tables)]
        S3[(S3<br/>documents)]
        SM[Secrets Manager<br/>per-service config]
        KMS[KMS<br/>encryption keys]
        BR[Bedrock]
        SNS[SNS + Lambda + SES<br/>alerting]
        CW[CloudWatch<br/>logs + VPC flow logs]
        WAF[WAF]
    end

    U -->|HTTPS| R53 --> NLB --> APPNS
    ACM -.->|TLS| NLB
    GH -->|OIDC, no static keys| ECR
    GH -->|terraform apply| VPC
    GH -->|push image tag| GitOps[(gitops repo)]
    ARGONS -->|sync| APPNS
    APPNS -->|IRSA| DDB
    APPNS -->|IRSA| S3
    APPNS -->|IRSA| SM
    APPNS -->|IRSA| BR
    NODES --> NAT --> Internet
    KMS -.->|encrypts| DDB
    KMS -.->|encrypts| S3
    KMS -.->|encrypts| SM
```

**Key infrastructure decisions:**
- **2 Availability Zones** — EKS requires a minimum of 2; keeps NAT/subnet cost down vs 3.
- **NLB (not ALB)** — provisioned by the AWS Load Balancer Controller from Kgateway's Gateway. TLS terminates at the NLB using the ACM wildcard cert.
- **IRSA (IAM Roles for Service Accounts)** — each service's pod assumes a scoped IAM role via the cluster's OIDC provider; no static AWS keys in the cluster.
- **OIDC for CI/CD** — GitHub Actions assumes an AWS role via OIDC federation; no long-lived secrets in GitHub.
- **KMS everywhere** — DynamoDB, S3, Secrets Manager, SNS, CloudWatch logs all encrypted with customer-managed keys.
- **Secrets Manager** — per-service runtime config (JWT secret, model IDs, bucket names); fetched by each service at startup. Never in Terraform state.
- **Account-level singletons** (ECR, ACM, Route53, OIDC provider, DynamoDB, KMS) are `prevent_destroy`-guarded and created once via a `create_global_resources` flag.

---

## 3. CI/CD & GitOps Flow

```mermaid
graph LR
    DEV[feature/* branch] -->|PR| DEVELOP[develop]
    DEVELOP -->|PR| MAIN[main]

    MAIN -->|push| BUILD[build.yml<br/>lint, SonarCloud, Snyk,<br/>build 6 images, Trivy scan,<br/>push to ECR, semver tag]
    BUILD -->|workflow_run| DEPLOY[deploy.yml<br/>read IRSA ARNs from TF state,<br/>bump image tag in gitops repo]
    DEPLOY -->|git push| GITOPS[(gitops repo<br/>values-prod.yaml)]
    GITOPS -->|auto-sync| ARGO[ArgoCD]
    ARGO -->|apply Helm| CLUSTER[EKS cluster]
```

- **App repo** (`build.yml` → `deploy.yml`): builds/scans/pushes images, then bumps the image tag in the gitops repo's Helm values.
- **GitOps repo**: ArgoCD watches it and auto-syncs any change to the cluster (Helm chart = single source of truth for cluster state).
- **Infra repo** (`terraform-apply.yml`): plan → manual approval → apply, with tfsec scanning.
- **Branching**: `main ← develop ← feature/*` across all 3 repos. Semantic versioning on `main` (`feat!:` → major bump).

---

## 4. Security & Observability

- **NetworkPolicies** — default-deny in `procurement-prod`, with explicit allows only for real traffic paths (Gateway→service, ai-service→its 4 peers, DNS, AWS APIs). Enforced by the AWS VPC CNI's native policy engine.
- **Scanning** — tfsec + Checkov (Terraform), SonarCloud + Snyk (app code/deps), Trivy (container images).
- **Monitoring** — kube-prometheus-stack: Prometheus scrapes cluster + app `/metrics` (via ServiceMonitors), Grafana dashboards (cluster + custom app RED-metrics dashboard), Alertmanager → Slack.
- **Alerting** — CloudWatch alarms → SNS → Lambda → SES email; plus Alertmanager → Slack for cluster alerts.
- **Audit** — every mutating action writes a `Document_AuditLog` entry; VPC flow logs + EKS control-plane logs to CloudWatch.
