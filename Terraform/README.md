# PulseGuard — Terraform Infrastructure

This provisions everything PulseGuard runs on: a self-managed kubeadm cluster
(1 master + 3 workers, all `t3.micro`) on EC2, RDS Postgres, an ALB, a
CloudFront distribution in front of it, ECR repos for the app images, and
every secret the app needs in SSM Parameter Store. No AWS Console clicks —
everything here is created and destroyed through Terraform.

## Architecture

```
GitHub → GitHub Actions (CI) → ECR ──┐
                                       ├──> ArgoCD watches manifests repo
                                       │    → syncs to the kubeadm cluster
                                       │
Route53 (status.saimm.online)
  → CloudFront (TLS termination, edge caching)
    → ALB (HTTP only — see "Why no HTTPS on the ALB" below)
      → NodePort 30080 on worker nodes
        → ingress-nginx → PulseGuard pods

VPC (10.0.0.0/16), 3 AZs (ap-south-1a/b/c)
  Public subnets  → master + 3 workers (all have public IPs, SSH + kubectl reachable)
  Private subnets → RDS Postgres only (no NAT Gateway — RDS never dials out)
```

## Directory layout

```
terraform-bootstrap/   # Run once, first. Creates the S3 bucket + DynamoDB
                        # table that the main config stores its state in.
                        # Uses LOCAL state (chicken-and-egg: this is what
                        # creates the remote backend, so it can't use it).

Terraform/              # Everything else. Uses the S3 backend created above.
  backend.tf             # S3 backend block (bucket/table passed at init time)
  providers.tf           # aws provider + us-east-1 alias (CloudFront needs
                          # its ACM cert issued in us-east-1, regardless of
                          # which region everything else lives in)
  variables.tf            # every input variable
  vpc.tf                   # VPC, IGW, 3 public + 3 private subnets, route tables
  security_groups.tf       # ALB / nodes / RDS security groups
  iam.tf                    # EC2 role with SSM access (Session Manager + our
                             # own SSM parameters, scoped to this project only)
  ec2.tf                     # 1 master + 3 workers (for_each), Ubuntu 22.04
  rds.tf                      # Postgres, private subnets, not publicly accessible
  ecr.tf                       # 2 image repos (web, checker) + lifecycle policies
  ssm.tf                        # every secret/config value the app and CI read
  acm.tf                         # ACM cert (us-east-1) for CloudFront, DNS-validated
  alb.tf                          # ALB → target group (port 30080) → workers only
  cloudfront.tf                    # CDN in front of the ALB + Route53 alias record
  outputs.tf                        # IPs, endpoints, URLs — feeds into Ansible next
```

## Prerequisites

1. **AWS account** with an IAM user/role that has API credentials, and the
   AWS CLI configured locally:
   ```bash
   aws configure
   ```
2. **Terraform** ≥ 1.6.0 installed locally.
3. **A domain** — this repo assumes `saimm.online` is already owned (registrar
   doesn't matter — Namecheap/GoDaddy/Hostinger/etc. all work, see the
   Route53 delegation step below).
4. **An EC2 key pair**, created in the **same region** you're deploying to
   (`ap-south-1` by default — key pairs are region-scoped):
   ```bash
   aws ec2 create-key-pair \
     --key-name pulseguard-key \
     --region ap-south-1 \
     --query 'KeyMaterial' \
     --output text > pulseguard-key.pem
   chmod 400 pulseguard-key.pem
   ```
5. **Your current public IP**, for the security group that gates SSH/kubectl
   access:
   ```bash
   curl -s ifconfig.me
   ```

## Setup — step by step

### 1. Bootstrap the state backend (once, ever)

```bash
cd terraform-bootstrap
echo 'state_bucket_name = "<globally-unique-bucket-name>"' > terraform.tfvars
terraform init
terraform plan   # expect: 5 to add (S3 bucket + versioning + encryption +
                  # public-access-block + DynamoDB lock table)
terraform apply
terraform output # note state_bucket and lock_table — needed in step 3
```

### 2. Delegate DNS to Route53 (only if your domain isn't already on Route53)

If your domain is registered elsewhere (Namecheap/GoDaddy/Hostinger/etc.),
`Terraform/acm.tf` creates the Route53 hosted zone itself
(`resource "aws_route53_zone" "root"`, not a `data` lookup — there's nothing
to look up yet). Create just that resource first, on its own:

```bash
cd ../Terraform
terraform init -backend-config="bucket=<state_bucket>" \
  -backend-config="region=ap-south-1" \
  -backend-config="dynamodb_table=<lock_table>"
terraform apply -target=aws_route53_zone.root
terraform output route53_name_servers
```

Take those 4 nameservers to your registrar's nameserver settings, replace
the defaults with them, save. Then wait for propagation and confirm before
continuing — the ACM certificate validation will hang indefinitely otherwise:

```bash
dig NS saimm.online +short
# must show the same 4 ns-xxxx.awsdns-xx.* values before moving on
```

*(If your domain is already a Route53 hosted zone, skip this step entirely
— just make sure `acm.tf` uses a `data "aws_route53_zone"` lookup instead of
a `resource`, since the zone already exists.)*

### 3. Configure variables

```bash
cat > terraform.tfvars << 'EOF'
my_ip    = "<your-ip>/32"
key_name = "pulseguard-key"
EOF
```

`my_ip` and `key_name` are deliberately left without defaults in
`variables.tf` — Terraform refuses to run without them rather than silently
reusing a stale value.

### 4. Plan and apply everything else

```bash
terraform plan
```

Confirm before applying:
- Every `aws_instance` shows `public_ip = (known after apply)` — if it
  shows nothing at all for that attribute, the instance is in a private
  subnet, which is wrong (nodes must be public; only RDS is private).
- No `aws_nat_gateway` or `aws_eip` anywhere in the plan.
- Roughly 50 resources total.

```bash
terraform apply
```

RDS takes the longest (5–10 min). Everything else is fast.

```bash
terraform output
```

Save these — `master_public_ip`, `worker_public_ips`, `rds_endpoint`,
`alb_dns_name`, `cloudfront_domain`, `public_url` all feed directly into the
Ansible inventory next.

## Variables reference

| Variable | Default | Notes |
|---|---|---|
| `aws_region` | `ap-south-1` | |
| `project_name` | `pulseguard-app` | prefixes every resource name |
| `environment` | `dev` | **must be lowercase** — AWS rejects uppercase in several resource-naming fields (RDS subnet group name, etc.) |
| `vpc_cidr` | `10.0.0.0/16` | |
| `public_subnet_cidrs` / `private_subnet_cidrs` | 3× `/24` each | one per AZ |
| `my_ip` | *(required, no default)* | your current public IP, `/32`. Changes when your ISP reassigns you one — see "Updating my_ip" below |
| `key_name` | *(required, no default)* | EC2 key pair **name**, not the `.pem` filename |
| `instance_type` | `t3.micro` | every node, master and worker alike |
| `worker_nodes` | 3 workers, `subnet_index` 0/1/0 | spreads workers across AZs — `for_each` over a map, not `count`, so adding/removing a worker doesn't shift/recreate the others |
| `db_name` / `db_username` | `appdb` / `postgres` | |
| `db_instance_class` | `db.t3.micro` | check available Postgres versions per region before assuming a specific `engine_version` works — see Troubleshooting |
| `domain_name` / `subdomain` | `saimm.online` / `status` | → `status.saimm.online` |

## Outputs reference

| Output | Used for |
|---|---|
| `master_public_ip`, `worker_public_ips` | Ansible inventory (Phase 3) |
| `rds_endpoint` | `DATABASE_URL` (already in SSM, but useful for manual debugging) |
| `alb_dns_name` | Sanity-checking the ALB directly, bypassing CloudFront |
| `cloudfront_domain` | The `*.cloudfront.net` fallback hostname |
| `public_url` | `https://status.saimm.online` — the actual app URL once deployed |
| `ecr_web_repo`, `ecr_checker_repo` | CI pushes images here |
| `ssm_prefix` | `/pulseguard-app/dev` — where every secret lives |
| `route53_name_servers` | Only present if you created the zone yourself (step 2) |

## Design decisions worth knowing

**Why nodes are in public subnets, not private:** SSH and `kubectl` need a
direct path from your laptop to the nodes. A private subnet has no route to
an Internet Gateway, so nothing in it is reachable from outside the VPC —
Ansible and `kubectl` would have no way in. RDS is the only thing in the
private subnets, and it's never dialed into or out from directly.

**Why there's no NAT Gateway:** NAT costs ~$32/month and exists so that
things in a private subnet can reach the internet *outbound* (e.g. for OS
updates). RDS is the only occupant of the private subnets, and it never
needs outbound internet access — AWS manages its patching at the
hypervisor level, not through your VPC routing. A NAT Gateway here would be
pure waste.

**Why the ALB has no HTTPS listener:** CloudFront terminates TLS at the edge
and talks to the ALB over plain HTTP — that hop stays entirely inside AWS's
network. This sidesteps needing an ACM cert bound to the ALB's
auto-generated `*.elb.amazonaws.com` DNS name (ACM won't issue for that).

**Why `worker_nodes` is `for_each` over a map, not `count`:** with `count`,
removing `worker-2` from a 3-item list shifts indices, and Terraform
destroys/recreates `worker-3` even though you never touched it. `for_each`
over named keys gives each worker a stable identity.

## Updating `my_ip`

Home/mobile ISPs hand out dynamic IPs. If SSH or `kubectl` suddenly stops
connecting, your IP probably changed:

```bash
curl -s ifconfig.me
terraform apply -var="my_ip=<new-ip>/32"
```

This only patches the one security group rule — no instances are touched,
no downtime. Every node also has SSM Session Manager access
(`aws ssm start-session --target <instance-id>`) as a fallback that doesn't
depend on your IP at all, since it's an outbound connection from the
instance.

## Troubleshooting — issues actually hit building this

- **`InvalidKeyPair.NotFound`**: the key pair exists in a different region
  than you're deploying to. Key pairs are region-scoped. Recreate it with
  `--region ap-south-1` explicitly, or check where it currently lives:
  `aws ec2 describe-key-pairs --region ap-south-1 --key-names <name>`.

- **`InvalidParameterCombination: Cannot find version X.Y for postgres`**:
  not every Postgres minor version is available in every region, and this
  changes over time. Check what's actually offered before pinning a
  version:
  ```bash
  aws rds describe-db-engine-versions --engine postgres --region ap-south-1 \
    --query "DBEngineVersions[?starts_with(EngineVersion, '16')].EngineVersion" \
    --output table
  ```

- **`only lowercase alphanumeric characters... allowed in "name"`**: several
  AWS resource-naming fields (RDS subnet group, RDS identifier, ECR repo
  names) reject uppercase. Keep `environment` lowercase from the start —
  this repo uses `dev`, not `Dev`.

- **`no matching Route 53 Hosted Zone found`**: the domain isn't a Route53
  hosted zone yet. See "Delegate DNS to Route53" above.

- **`Invalid index` on subnet CIDR lookups**: if `count` for subnets is
  driven by `length(data.aws_availability_zones.available.names)` instead
  of the CIDR list length, and the region has more AZs than you have CIDR
  blocks defined, Terraform tries to index past the end of the list. Drive
  `count` from the CIDR list length instead.

- **Accidentally committed `.terraform/` (700+ MB provider binary)**:
  GitHub rejects pushes over 100MB per file. Fix: `git reset --soft HEAD~1`,
  add `.terraform/`, `*.tfstate`, `*.tfstate.backup`, `*.pem`, and
  `terraform.tfvars` to `.gitignore`, then re-add and re-commit. Never
  commit `.terraform/` — it's a local cache, rebuilt by `terraform init`.

## Tearing down

Destroy in reverse order — main config first, bootstrap last (bootstrap
holds the state that the main config's destroy needs to run):

```bash
cd Terraform
terraform destroy

cd ../terraform-bootstrap
terraform destroy   # only once nothing else depends on this bucket/table
```

## What never goes in git

`.gitignore` in both `terraform-bootstrap/` and `Terraform/` excludes:
`.terraform/`, `*.tfstate`, `*.tfstate.backup`, `*.pem`, `terraform.tfvars`.
None of these were ever committed in this repo's history — verified with:
```bash
git log --all --full-history -- '**/*.pem' '**/terraform.tfvars' '**/*.tfstate'
```
(empty output = clean).