# procurement-platform-infra

Terraform for the Procurement Platform's AWS infrastructure only — VPC, EKS, ECR, ACM, Route53,
IAM/IRSA, Secrets Manager, DynamoDB, S3, CloudWatch, SNS/Lambda/SES (monitoring alerts), WAF, and
cluster add-ons (AWS Load Balancer Controller, EBS CSI Driver, Metrics Server). It does not deploy
the application or install ArgoCD — see the other two repos in this org for that.

## Structure

Flat root module + `modules/`. No `environments/` folder — `dev` and `prod` are Terraform
workspaces, since the infra is nearly identical between them. Environment-specific values live in
`dev.tfvars` / `prod.tfvars`. Account-level singletons (ECR, ACM, Route53, GitHub OIDC roles, SES
identities) are gated behind `create_global_resources` and created once, alongside whichever
workspace's first apply you choose to hold them — never duplicated into the other workspace.

**Important:** whichever workspace's state holds the singletons must always pass
`create_global_resources=true` on every future apply of that workspace. Passing `false` there
after they already exist would tell Terraform to destroy them — `prevent_destroy` on the ACM cert
and Route53 zone will block that and error loudly instead, but don't rely on it; just always pass
the flag consistently for whichever workspace you picked, and never pass it for the other one.

## Account portability (switching AWS accounts)

The backend bucket name is **not** hardcoded — `backend.tf` is a partial config, the actual
bucket/region/dynamodb_table come from `-backend-config` flags at init time (see
`backend.hcl.example`). This is what makes switching AWS accounts (e.g. personal → training
account) just a different init command, not a code edit. **S3 bucket names are globally unique
across all of AWS**, not just your account — you cannot reuse the same bucket name in a different
account, even though DynamoDB table names can repeat freely across accounts.

```bash
aws sts get-caller-identity   # confirm you're authenticated against the account you intend to use

aws s3api create-bucket --bucket <new-globally-unique-name> --region us-east-1
aws s3api put-bucket-versioning --bucket <new-globally-unique-name> --versioning-configuration Status=Enabled
aws dynamodb create-table --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

terraform init -reconfigure \
  -backend-config="bucket=<new-globally-unique-name>" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=terraform-state-lock"
```
In CI, set the `TF_STATE_BUCKET` repo **secret** (not a variable — same reasoning as
`AWS_OIDC_ROLE_ARN` below) to the same bucket name — `terraform-apply.yml` passes it the same way.

## Applying

```bash
terraform workspace new dev    # or prod — whichever you pick first holds the singletons
terraform apply -var-file=dev.tfvars -var="create_global_resources=true"

# create_global_resources=true here creates the ECR repos, ACM cert, Route53
# zone, GitHub OIDC roles, and SES identities ONCE. Do not pass it on the
# other workspace's apply — those resources already exist account-wide.
terraform workspace new prod
terraform apply -var-file=prod.tfvars
```
No two-step `-target` apply needed — there's no `helm`/`kubernetes` provider in this repo (see
"Cluster add-ons" below for why), so nothing in the provider config depends on resources that
don't exist yet at plan time. Single `terraform apply` is enough, even on a brand-new cluster.

### Cluster add-ons (AWS Load Balancer Controller, EBS CSI Driver, Metrics Server)

Their IAM roles are created here (`modules/eks`, `modules/eks-addons`), but the actual `helm
install` happens in `scripts/bootstrap-cluster.sh`, not as Terraform `helm_release` resources.
Terraform's `helm`/`kubernetes` provider computes its auth token once during `terraform apply`,
right as the cluster is newly created — that can race an EKS access-entry propagation window and
fail with "the server has asked for the client to provide credentials." A separate, later CLI
step re-authenticates fresh and isn't subject to that timing window. Same reasoning Kgateway and
ArgoCD already use below.

### Using the Ubuntu node AMI instead of Amazon Linux

`var.use_ubuntu_ami` defaults to `false`. Turning it on switches the node group to Canonical's
EKS-optimized Ubuntu AMI via an SSM parameter lookup — **this is the highest-risk single setting
in this repo**: if the AMI/bootstrap doesn't match what this cluster's k8s version expects, nodes
never report `Ready` and the node group hangs in `Still creating...` indefinitely (the exact
failure mode hit during initial setup, just with a different root cause). Before enabling it:

```bash
aws ssm get-parameter --name /aws/service/canonical/ubuntu/eks/22.04/1.30/stable/current/amd64/hvm/ebs-gp2/ami-id --region us-east-1
```
Confirm that resolves to a real AMI ID in your account/region first. Then:
```bash
terraform apply -var-file=dev.tfvars -var="create_global_resources=true" -var="use_ubuntu_ami=true"
```
**Watch the node group creation closely — if it's not `Active` within ~10 minutes, abort
(`Ctrl+C` once, then `terraform destroy`) rather than waiting 30+ minutes.** Reverting is just
dropping `-var="use_ubuntu_ami=true"` from the next apply.

After each environment's apply, run `scripts/bootstrap-cluster.sh <dev|prod>` manually. It installs
everything that runs inside the cluster but isn't a Terraform resource, in order: the LB
Controller/EBS CSI/Metrics Server helm charts, the kube-prometheus-stack (Prometheus + Grafana +
Alertmanager) for monitoring, Kgateway + the Gateway API CRDs, and ArgoCD — then applies the
App-of-Apps from
[procurement-platform-gitops](https://github.com/ProcurementPlatform/procurement-platform-gitops).
This is never run from CI. Grafana/Prometheus stay ClusterIP (no extra ELB cost) — reach them via
the `kubectl port-forward` commands the script prints when it finishes.

## Phase 2: enabling CloudFront

CloudFront fronts the load balancer Kgateway's Gateway provisions (an NLB, via the AWS Load
Balancer Controller) — but that doesn't exist until ArgoCD has synced the Gateway from the gitops
repo, which only happens after `bootstrap-cluster.sh` has run. So CloudFront is always a
**second, later apply**, never part of the first one above:

```bash
kubectl get svc -A | grep LoadBalancer   # find the Gateway's Service, copy its EXTERNAL-IP/hostname

terraform apply -var-file=dev.tfvars -var="create_global_resources=true" \
  -var="enable_cloudfront=true" \
  -var="alb_dns_name=<nlb-hostname-from-above>" \
  -var="acm_certificate_arn=$(terraform output -raw acm_certificate_arn)" \
  -var="route53_zone_id=$(terraform output -raw route53_zone_id)"
```

Same idea for the other workspace, except `acm_certificate_arn`/`route53_zone_id` (and, for the
Lambda alert function, `ses_sender_identity_arn`) still come from whichever workspace's outputs
hold the singletons, even though you're applying somewhere else.

## After the first apply that creates the singletons

```bash
aws route53 get-hosted-zone --id $(terraform output -raw route53_zone_id) --query 'DelegationSet.NameServers' --output table
```
Update your domain registrar's nameservers to these 4 values — the hosted zone only becomes the
real DNS authority for the domain once the registrar delegates to it.

## Related repos

- [procurement-platform-app](https://github.com/ProcurementPlatform/procurement-platform-app) — backend/frontend source + build/deploy CI
- [procurement-platform-gitops](https://github.com/ProcurementPlatform/procurement-platform-gitops) — Helm chart + ArgoCD Application manifests
