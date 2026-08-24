# AWS — Terraform deployment root

This folder is the **only** place Terraform is executed. Everything beside it is
a reusable resource module.

```
AWS/
├── main.tf                     module calls — the deployment entry point
├── providers.tf                the single provider configuration
├── versions.tf                 version pins + S3 backend
├── variables.tf                root inputs
├── locals.tf                   naming + tagging convention
├── outputs.tf                  root outputs
├── terraform.tfvars            the deployment values (auto-loaded)
├── .terraform.lock.hcl         pinned provider checksums
├── .tflint.hcl                 lint ruleset for root + all modules
└── S3/                         resource module (no provider, no backend)
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── versions.tf
```

## Why it is shaped this way

| Decision | Reason |
| --- | --- |
| One root, many resource folders | A single `terraform apply` produces one coherent state. Cross-resource wiring (bucket ARN → IAM policy) is a plain reference, not a `terraform_remote_state` lookup. |
| Modules have no `provider` block | Region and credentials are decided once, at the root. The same `./S3` module works in any account or region without edits. |
| `for_each` over a map in the root | Adding a bucket is a `terraform.tfvars` change, not a code change. Map keys are the state addresses, so blast radius stays per-bucket. |
| Backend configured inline | Single deployment, single state file — `terraform init` needs no flags. |
| Plan artifact applied in a second job | The apply executes the exact plan that was reviewed and approved. |

## Adding a new resource type

1. `mkdir AWS/EC2` and write `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`.
   Do **not** add `provider` or `backend` blocks.
2. Add a `module "ec2" { source = "./EC2" ... }` block to [main.tf](main.tf).
3. Add its input variable to [variables.tf](variables.tf) and outputs to [outputs.tf](outputs.tf).
4. Set values in [terraform.tfvars](terraform.tfvars).

Nothing in the pipeline needs to change — it plans and applies whatever the root
module contains.

## Adding a new bucket

Add an entry to `s3_buckets` in [terraform.tfvars](terraform.tfvars):

```hcl
s3_buckets = {
  "user-uploads" = {
    sse_algorithm      = "aws:kms"
    create_kms_key     = true
    versioning_enabled = true

    logging = {
      target_bucket_key = "access-logs"   # another key in this same map
      target_prefix     = "user-uploads/"
    }

    lifecycle_rules = [
      {
        id                                     = "expire-noncurrent"
        abort_incomplete_multipart_upload_days = 7
        noncurrent_version_expiration          = { noncurrent_days = 30 }
      },
    ]
  }
}
```

### Naming the bucket

Two options per entry.

**Set the name yourself** — `bucket_name` is used verbatim, with no prefix and
no suffix:

```hcl
"app-artifacts" = {
  bucket_name = "shouvik-dev-v7"
  ...
}
```

**Or let it be generated** — omit `bucket_name` and the physical name becomes
`<project>-<key>-<account_id>`, e.g. `shouvik-dev-user-uploads-123456789012`.
Set `append_account_id_to_bucket_names = false` to drop the account suffix.

S3 names are **globally unique across every AWS account** and must be 3-63
characters of lowercase letters, digits, hyphens or dots — uppercase is
rejected, so `shouvik-dev-V7` is not a legal name. A root validation catches
this at plan time and tells you which map key is at fault.

`logging` takes **either** `target_bucket_key` (another key in the map — the
generated name is resolved for you, so nothing is hard-coded) **or**
`target_bucket` (an external bucket name). Setting both, or neither, fails
validation.

> **The map key is the state address.** Renaming a key destroys and recreates
> the bucket. Use `terraform state mv` if a rename is genuinely needed.

## Running locally

The backend is a partial configuration, so `terraform init` needs the state
bucket passed in — see [Remote state](#remote-state) below for the exact
commands. After that, `terraform plan` and `terraform apply` need no flags:
`terraform.tfvars` is loaded automatically.

## Provider lock file

`.terraform.lock.hcl` is committed and pins `hashicorp/aws` to a single version
with checksums for `linux_amd64` (CI), `darwin_arm64` and `windows_amd64`. CI
runs `terraform init` against it, so a provider release cannot change what gets
planned without a reviewed commit.

To add a platform or bump the provider:

```bash
terraform providers lock -platform=linux_arm64      # add a platform
terraform init -upgrade                             # bump within the constraint
```

> `windows_arm64` is deliberately absent — HashiCorp does not publish an AWS
> provider build for it, so Terraform cannot run locally on an ARM Windows
> machine. Use WSL2 or the pipeline.

## Remote state

State lives at `s3://<state-bucket>/aws/terraform.tfstate`, where the bucket is
named `<state_bucket_prefix>-<account-id>` (default prefix
`shouvik-dev-tfstate`). Native S3 locking (`use_lockfile = true`) means no
DynamoDB table is needed.

**The pipeline creates this bucket for you.** The state bucket cannot be
managed by the state it stores, so the *Ensure state bucket exists* step in
[terraform-reusable.yml](../.github/workflows/terraform-reusable.yml) creates
it out of band on first run — versioned, encrypted, and with public access
blocked — then passes its name to `terraform init`. After the first run the
step is a single `head-bucket` check.

Change the prefix with the `state_bucket_prefix` input in the caller workflows.

> The account id is resolved at runtime, which is why the `backend "s3"` block
> in [versions.tf](versions.tf) is a **partial** configuration: `bucket` and
> `region` are supplied via `-backend-config` rather than hard-coded.

### Running locally

Because the backend is partial, a local `terraform init` needs the bucket
passed explicitly:

```bash
cd AWS
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

terraform init \
  -backend-config="bucket=shouvik-dev-tfstate-${ACCOUNT}" \
  -backend-config="region=ap-south-1"

terraform plan
```

## Placeholders to replace before first use

| Where | Value |
| --- | --- |
| [terraform.tfvars](terraform.tfvars) | `project`, `owner`, `cost_center`, `aws_region`, and each `bucket_name` |
| GitHub Actions **Secrets** | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` |

## Pipeline

See [../.github/workflows/README.md](../.github/workflows/README.md) for the
CI/CD contract and the IAM/OIDC setup it depends on.
