# CI/CD contract

Four workflows, one engine, one deployment.

| Workflow | Trigger | What it does |
| --- | --- | --- |
| `terraform-reusable.yml` | `workflow_call` | The engine: fmt → init → validate → tflint → Trivy → plan → (optional) apply. Never runs on its own. |
| `terraform-plan.yml` | PR to `main` touching `AWS/**` | Validates and plans. Posts one self-updating PR comment. Applies nothing. |
| `terraform-apply.yml` | Push to `main`, or manual | Re-plans the merged commit and applies it. |
| `terraform-destroy.yml` | Manual only | Destroy plan + apply. Requires typing `DESTROY`. |

## Guarantees

- **No static AWS keys.** Authentication is GitHub OIDC → IAM role.
- **Plan/apply separation.** `plan` runs under a read-only role and uploads a
  binary plan file; `apply` downloads that artifact and runs it. What was
  reviewed is what executes.
- **No-op applies are skipped.** `terraform plan -detailed-exitcode` returns 2
  only when there are changes; the apply job is conditioned on it.
- **Approvals live in a GitHub Environment,** not in workflow YAML, so changing
  who can approve is not a code change.
- **Applies are serialised** via a `concurrency` group, so two merges cannot
  race for the state lock.

## One-time setup

### 1. GitHub OIDC provider in the AWS account

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### 2. IAM roles

Create `gha-terraform-apply` with the permissions Terraform actually needs, and
optionally `gha-terraform-plan` with read-only access. Trust policy — scope
`sub` as tightly as the branch model allows:

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

Both roles need read/write on the state bucket prefix (`s3:GetObject`,
`PutObject`, `DeleteObject`, `ListBucket`) — the plan role included, because
Terraform writes a lock object.

### 3. Repository variables

Settings → Secrets and variables → Actions → **Variables** (these are role ARNs
and a region, not secrets):

| Variable | Required | Example |
| --- | --- | --- |
| `AWS_ROLE_ARN` | yes | `arn:aws:iam::123456789012:role/gha-terraform-apply` |
| `AWS_REGION` | yes | `ap-south-1` |
| `AWS_PLAN_ROLE_ARN` | optional | `arn:aws:iam::123456789012:role/gha-terraform-plan` — falls back to `AWS_ROLE_ARN` |

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

## Artifact note

The uploaded plan artifact includes `tfplan.json`, which contains resolved
variable values. Retention is 5 days; keep repository artifact access limited to
the team that can already read the state bucket.
