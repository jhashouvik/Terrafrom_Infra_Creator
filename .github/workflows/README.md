# CI/CD contract

Four workflows, one engine, one deployment.

| Workflow | Trigger | What it does |
| --- | --- | --- |
| `terraform-reusable.yml` | `workflow_call` | The engine: fmt → init → validate → tflint → Trivy → plan → (optional) apply. Never runs on its own. |
| `terraform-plan.yml` | PR to `main` touching `AWS/**` | Validates and plans. Posts one self-updating PR comment. Applies nothing. |
| `terraform-apply.yml` | Push to `main`, or manual | Re-plans the merged commit and applies it. |
| `terraform-destroy.yml` | Manual only | Destroy plan + apply. Requires typing `DESTROY`. |

## Guarantees

- **Static IAM access keys**, held in GitHub Actions **Secrets** (never
  Variables, which are plaintext and echoed into logs). They are long-lived:
  rotate them on a schedule. Switching to OIDC removes them entirely.
- **Plan/apply separation.** `plan` uploads a binary plan file; `apply`
  downloads that artifact and runs it. What was reviewed is what executes.
  (With a single key pair, plan and apply share credentials - the separate
  read-only plan role is an OIDC-only benefit.)
- **No-op applies are skipped.** `terraform plan -detailed-exitcode` returns 2
  only when there are changes; the apply job is conditioned on it.
- **Approvals live in a GitHub Environment,** not in workflow YAML, so changing
  who can approve is not a code change.
- **Applies are serialised** via a `concurrency` group, so two merges cannot
  race for the state lock.

## One-time setup

### 1. IAM user and access keys

AWS console → **IAM → Users → Create user** (no console access needed), then
**Security credentials → Create access key → Command Line Interface**.

Permissions the current configuration actually needs:

- **S3** — for the managed buckets *and* the state bucket. `AmazonS3FullAccess`
  covers both; a narrower custom policy must include the state bucket, since
  Terraform reads, writes and lock-stamps objects there.
- **KMS** — only if any bucket sets `create_kms_key = true`. The shipped
  `terraform.tfvars` uses `AES256`, so this is not currently required. Attach
  `AWSKeyManagementServicePowerUser` if you switch to a customer-managed CMK.
- **IAM** — only if a bucket configures `replication`, which creates a role.

`sts:GetCallerIdentity` is needed by [locals.tf](../../AWS/locals.tf) and is
allowed for every principal by default.

> These keys are long-lived. Rotate them on a schedule, and delete the old key
> in IAM once the new one is in place.

### 2. Migrating to OIDC later (optional, recommended)

Static keys can be removed entirely by federating GitHub Actions into an IAM
role instead:

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com
```

Then create a role whose trust policy scopes `sub` to this repository:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": [
          "repo:<ORG>/<REPO>:ref:refs/heads/main",
          "repo:<ORG>/<REPO>:pull_request",
          "repo:<ORG>/<REPO>:environment:aws"
        ]
      }
    }
  }]
}
```

Swap the `aws-access-key-id` / `aws-secret-access-key` inputs in
[terraform-reusable.yml](terraform-reusable.yml) for `role-to-assume`, restore
`id-token: write` on the jobs, and delete the two secrets.
### 3. Repository secrets

Settings → Secrets and variables → Actions → **Secrets** tab:

| Secret | Required |
| --- | --- |
| `AWS_ACCESS_KEY_ID` | yes |
| `AWS_SECRET_ACCESS_KEY` | yes |

> Never put these under the **Variables** tab. Variables are stored in
> cleartext and echoed into workflow logs; only Secrets are encrypted and
> masked.

**No repository variables are required.** The region is not one: where
resources are created is decided by `aws_region` in
[../../AWS/terraform.tfvars](../../AWS/terraform.tfvars), which
[providers.tf](../../AWS/providers.tf) reads. The pipeline's `aws_region`
input (default `ap-south-1`) only picks the endpoint used to authenticate and
to reach the state bucket — override it in the caller workflows if you move
regions.

### 4. The `aws` GitHub Environment

Settings → Environments → **New environment** → `aws`.

Add required reviewers to it if you want a manual approval before every apply,
and restrict deployment branches to `main`. If you skip this step GitHub creates
the environment on first run with no protection, and applies proceed
automatically.

### 5. Branch protection on `main`

Require the `plan` check plus at least one review.

## Tuning

- **Terraform version** — `terraform_version` input, default `1.13.1`. Change it
  in the caller workflows.
- **Security gate strictness** — the Trivy step fails on `HIGH,CRITICAL`. Drop
  `HIGH`, or set `exit-code: "0"` to report without blocking, in
  `terraform-reusable.yml`.
- **Approval gate name** — `approval_environment` input, default `aws`.
- **Auth region** — `aws_region` input, default `ap-south-1`. Only affects the
  STS and state-bucket endpoints; the deployment region is `aws_region` in
  `AWS/terraform.tfvars`.

## Artifact note

The uploaded plan artifact includes `tfplan.json`, which contains resolved
variable values. Retention is 5 days; keep repository artifact access limited to
the team that can already read the state bucket.
