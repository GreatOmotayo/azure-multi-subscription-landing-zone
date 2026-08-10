# Decision Log — Multi-Subscription Azure Landing Zone

This document captures the reasoning behind each significant design decision in this project — what was chosen, what alternatives were considered, and why. It also documents real issues hit during the build, since a decision log without failure history isn't an honest one.

---

## Phase 1: Management Group Hierarchy

### Decision: Intermediate root MG (`mg-reale-root`) instead of building directly under Tenant Root Group

Tenant Root Group has special, largely irreversible behavior — policy assigned there applies tenant-wide with no exclusion path, and very few identities should ever touch it. Industry pattern (Microsoft's Cloud Adoption Framework "Enterprise-Scale" reference architecture) is to create one intermediate MG directly below root and do all real governance work below that, leaving root untouched.

**Alternative considered:** Build directly under Tenant Root Group, since this project only has 2–3 subscriptions.
**Rejected because:** the project's value is in demonstrating the enterprise pattern correctly, not in minimizing MG count for a small subscription set.

### Decision: Platform / Landing Zones (Production, NonProd) / Decommissioned structure

- **Platform** isolates shared infrastructure, which needs different (often looser) network policy but tighter RBAC than workload subscriptions.
- **Production vs. NonProd split** allows differentiated policy strictness — a single "Landing Zones" bucket would force identical enforcement on environments with very different risk profiles.
- **Decommissioned** exists as a holding area with maximum-restriction policy for subscriptions being retired, rather than leaving them in their prior MG (still inheriting live policy) or in limbo with none.

**Alternative considered:** Flat structure, subscriptions directly under Landing Zones.
**Rejected because:** the hierarchy demonstrates design judgment independent of subscription count, and costs nothing extra to build correctly.

### Decision: `azurerm_management_group_subscription_association` (separate resource) instead of inline `subscription_ids` on `azurerm_management_group`

The inline list is **authoritative** — Terraform will forcibly evict any subscription not present in that list on every `apply`, including ones added manually outside Terraform (e.g., during an incident). The separate association resource is **additive** — it manages exactly one relationship and ignores anything else attached to that MG.

**Why this matters:** subscriptions get reorganized outside IaC more often than teams admit. The additive approach prevents an unrelated policy-tweak `apply` from silently evicting a subscription that was added by another process.

### Decision: `mg-<purpose>` naming convention

Matches Microsoft CAF guidance, sorts and reads cleanly in the portal. Rejected company-prefixed naming (overkill for single-tenant use) and GUID-based naming (unreadable). **Gotcha:** Management Group `name` (the ID) must be globally unique across all of Azure, not just this tenant — a `terraform apply` conflict on this resource means the ID string collided with someone else's, anywhere.

---

## Phase 2: Azure Policy

### Decision: Built-in policy definitions wherever they exist; custom only for genuine gaps

Built-ins are Microsoft-maintained and stay current as resource types and APIs evolve; a hand-written equivalent can silently go stale. Writing custom definitions for things that already exist as built-ins is generally a signal of not having checked what's available, not a demonstration of skill.

**Custom policy was still written** — one, for tag/scope drift detection (see below) — specifically to demonstrate the ability to author policy JSON where a genuine gap exists, not as the default approach.

### Decision: Bundle policies into a custom Initiative rather than assigning each individually

Assigning 5 policies individually across 3 management groups means up to 15 separate assignment resources to track. An Initiative groups them into one assignable, parameterized unit, and compliance reporting rolls up per-initiative rather than across 15 scattered states.

**Clarification on "Custom" policy_type:** the Initiative container itself is classified `Custom` because *you* assembled it — this is independent of whether the individual policies referenced inside it are built-in. Built-in initiatives (e.g., Azure Security Benchmark) were considered and rejected for this project because they bundle 200+ policies with no individual review, which undermines the goal of being able to explain every guardrail specifically.

### Decision: Differentiated policy effects per environment, not uniform `Deny`

| Policy | Platform | Production | NonProd |
|---|---|---|---|
| Deny public IPs | Audit | Deny | Audit |
| Require tags | Deny | Deny | Deny |
| Allowed regions | Deny | Deny | Deny |
| Allowed VM SKUs | Audit | Deny | Deny |
| Encryption (CMK) | Deny | Deny | Audit |

Uniform `Deny` looks safest on paper but drives teams to route around governance entirely when it blocks legitimate exceptions (Platform needing a public Application Gateway; NonProd needing SKU/testing flexibility). Tags and region restriction are cheap to comply with and have no legitimate exception, so `Deny` is safe there; public IP and SKU restriction have real exceptions, so `Audit` there preserves visibility without blocking real work.

### Decision: Assign the Initiative once per Management Group, with different parameters, rather than once at root

Azure Policy parameters are fixed per assignment. Since effects genuinely need to differ per environment, a single root-level assignment would force identical enforcement everywhere, contradicting the differentiated-effects decision above.

### Decision: One custom policy — Environment tag must match deployment scope

Denies resources tagged `Environment=Production` when deployed under a resource group whose name contains "nonprod," catching a real-world drift pattern (tag/scope mismatch) that no built-in policy covers directly.

**Known limitation, documented rather than hidden:** the rule checks resource group *naming convention* as a proxy for management group ancestry, since Azure Policy's alias support for MG ancestry is limited. A more robust version would check true MG ancestry via policy alias if that becomes available.

---

## Phase 3: RBAC

### Decision: Start from built-in roles; custom only where there's a genuine permissions gap

| Persona | Considered built-in | Gap | Decision |
|---|---|---|---|
| Platform team | Contributor | Can create/delete any resource type, no scoping to actual job | Custom: Platform Infrastructure Operator |
| Production support | Contributor | Can delete resources, modify network/security — far beyond "keep prod running" | Custom: Production Support Operator |
| Dev/Test engineers | Contributor | Fits — NonProd is meant to be low-friction | Built-in, unchanged |
| Auditor | Reader | Already minimal and appropriate | Built-in, unchanged |
| CI/CD pipeline identity | Contributor | Needs deployment rights but must not self-elevate or grant/modify RBAC or Policy | Custom: Landing Zone Deployer |

### Decision: `Landing Zone Deployer` explicitly excludes `Microsoft.Authorization/*` write/delete actions

This closes the "self-elevation" loop — a real, common cloud security review finding, where a CI/CD identity with Contributor/Owner could in principle grant itself more access or disable the policies meant to constrain it. Even if the federated credential were compromised, the blast radius excludes privilege escalation and policy tampering.

### Decision: Assign custom/team roles at Management Group scope by default; Dev/Test Contributor at subscription scope as a deliberate exception

MG-scope assignment means any subscription added later under that MG automatically inherits the correct access with no manual re-assignment. Dev/Test is the deliberate exception: kept at subscription scope so that if a second subscription is later added under `mg-nonprod` without vetting, Contributor access doesn't apply to it automatically.

### Decision: Entra ID groups managed as Terraform resources (`azuread_group`), not created manually

Consistency with the rest of the project — leaving group creation as an untracked manual prerequisite would break the "everything reproducible via `terraform apply`/`destroy`" premise the whole project is built on.

**Requirement this introduces:** group creation needs Microsoft Graph API application permissions (`Group.ReadWrite.All`), which is a separate permission system from Azure RBAC — a role like Owner or Contributor on a subscription does not grant any rights over the Entra ID directory itself. This is a common point of confusion and a real gotcha documented in the CI/CD section below.

### Decision: All 4 test groups include the project owner as a member, via Terraform

Done deliberately to allow personal verification of every access boundary post-deployment. **Explicitly not a production pattern** — a single identity holding membership across Platform, Production Support, Dev/Test, and Auditor groups simultaneously violates the separation-of-duties principle the RBAC design otherwise establishes. Included here purely for testing/demonstration purposes, and documented as such rather than presented as a real-world default.

---

## Phase 4: Cost Controls

### Decision: Budgets scoped per-subscription, not per-management-group

A single MG-level budget signals "the landing zone is over budget" without indicating which environment caused it. Per-subscription budgets allow different thresholds and (potentially) different notification routing per environment, and map to distinct expected spend patterns (steady in Production, spiky in NonProd, flat in Platform).

### Decision: Direct Action Group → Email, not routed through the existing Cost Governance project's Function

**Originally considered:** routing budget alert webhooks through the `azure-cost-governance-and-waste-detection` project's existing Function App, to enrich alerts with top cost-driving resources and demonstrate cross-project integration.

**Reversed, deliberately.** Cross-project dependency via remote state means this project can no longer be deployed or reviewed independently — anyone evaluating this repo would need the other project's infrastructure live first. Independent deployability was judged more valuable than the richer alert content or the "systems thinking" narrative the integration would have told. Direct Action Group email is simpler, has no cross-project blast radius, and is a legitimate, common pattern on its own.

**Trade-off accepted:** no enrichment of alert content (no auto-surfaced top cost drivers) — plain Azure budget alert email only.

### Decision: Two-tier thresholds (80%/100%) on Production only; single 80% tier on Platform and NonProd

Production is where real overruns matter most, justifying an early-warning tier in addition to the over-budget tier. A second tier on the smaller, lower-stakes Platform/NonProd budgets would be alert fatigue for low-value signal.

### Correction: `azurerm_subscription_budget` renamed to `azurerm_consumption_budget_subscription` in provider v4

Caught via provider documentation check before applying, not via a failed `apply`. The `time_period` block also requires an explicit `end_date` in addition to `start_date` under the current schema — the original draft only had `start_date`.

### Finding: RBAC delete-restriction test invalidated by the project owner's standing Owner access

Attempted to validate that `Production Support Operator` correctly blocks delete actions by testing as the project owner's own account — the delete succeeded, which initially looked like a role-definition bug. Investigation (`az role assignment list --include-inherited`) revealed the project owner's own user account held `Owner` at 4 separate scopes (the Production subscription itself, plus `mg-reale-production`, `mg-reale-landingzones`, and `mg-reale-root`) — none of which were created by this project's Terraform, and all pre-dating or sitting alongside the intentional test-group memberships added in Phase 3.

Since Azure RBAC is additive, holding `Owner` anywhere in the scope chain overrides any narrower custom role's restrictions, regardless of how correctly that custom role's `not_actions` block is written. The test was structurally incapable of proving anything about the custom role while both roles applied to the same identity simultaneously.

**Resolution:** rather than removing the project owner's own standing Owner access (which would have blocked the owner's own path back into the tenant without a confirmed Global Administrator fallback), created 4 **dedicated test user accounts** — one per persona (Platform, Production Support, Dev/Test, Auditor) — each added to exactly one corresponding Entra ID group, with zero broader access. This mirrors real separation-of-duties practice more accurately than the original "add the owner to all 4 groups" approach, which was already flagged at the time as a testing-only compromise, not a production pattern.

**Naming note:** test user UPNs were created without a `test-` prefix (e.g., `platform@<tenant>.onmicrosoft.com` rather than `test-platform@<tenant>.onmicrosoft.com`). These are still identifiable as disposable test accounts via their Entra ID `displayName` field (`"Test - Platform Operator"`, etc.), even though the UPN itself doesn't carry that signal.

Managed via Terraform (`test-users.tf`) for consistency with the rest of the project's "everything reproducible via apply/destroy" principle, rather than left as untracked manual CLI-created accounts.

Attempted to strengthen `storageEncryptionEffect` from `Audit`-only to include `Deny`, intending to hard-enforce customer-managed-key encryption in Production. The Initiative parameter itself accepted the change, but `apply` failed with `PolicyParameterValueNotAllowed` — the underlying built-in policy (`6fac406b-40ca-413b-bf8e-0bf964659c25`, "Storage accounts should use customer-managed key for encryption") only supports `Audit` and `Disabled` as valid effects; `Deny` is not implemented for this specific built-in, independent of what the Initiative's own parameter allows.

**Reverted** `storageEncryptionEffect` to `Audit`-only across the Initiative and all assignments. Enforcing CMK via hard `Deny` would require a different built-in (if one exists with Deny support) or a custom policy definition — not pursued further for this project, since Audit-level visibility into non-compliant storage accounts was judged sufficient for the portfolio scope, and the built-in's Audit-only design likely reflects Microsoft's own view that Deny here risks blocking legitimate deployments on a Key Vault dependency that's easy to get wrong.

**Why this is worth documenting rather than hiding:** it demonstrates the two-layer constraint model in Azure Policy (Initiative-level `allowedValues` vs. the underlying built-in policy's own `allowedValues`) — a genuinely non-obvious distinction that isn't visible until you hit exactly this error.

---

## Phase 5: Module Structure & State

### Decision: Flat root module with logically separated files, not reusable Terraform modules

Modules earn their complexity when the same logic needs to be instantiated multiple times with different inputs. This project deploys one landing zone, once — there is no reuse case yet, and modules would add indirection (variables in, outputs out) that makes the repo harder to read end-to-end during recruiter/reviewer review, which matters more here than reuse that isn't needed.

**Explicit trigger for revisiting this decision:** if a second, near-identical landing zone is ever stood up (e.g., a second portfolio scenario), that is the point to extract `modules/management-group-hierarchy/`, `modules/policy-baseline/`, etc.

### Decision: Shared Terraform state storage account across portfolio projects, but a distinct `key` per project

One storage account for multiple projects' state is fine, since access is controlled by RBAC, not by how many projects share the account. The distinct `key` per project is what actually enforces independence — shared state files would mean a mistake in one project's `apply` could corrupt or modify resources belonging to another.

### Decision: State storage located in the Platform subscription, not a separate dedicated "state" subscription

Platform's defined purpose is shared infrastructure; state storage fits that category. A fully separate, isolated subscription for state (so that nothing with the ability to modify all infrastructure state also lives inside infrastructure that state manages) is the stricter posture some enterprises use, and was considered — but judged unnecessary complexity for this project's scale. Documented as a deliberate simplification, not an oversight.

---

## Phase 6: CI/CD

### Decision: Reuse the CI/CD pipeline project's OIDC architecture rather than building a new pattern

Consistency across portfolio repos is itself a signal of disciplined practice. Same three-job structure (plan on PR, apply on merge) as the existing `azure-terraform-cicd-pipeline` project.

### Decision: A GitHub Environment (`production`) with required reviewer gates the `apply` job

Justified by proportional blast radius — a bad `apply` in the containerized web app project redeploys a container; a bad `apply` here can misassign tenant-wide RBAC or lock out access via an overly strict policy. The approval gate matches friction to actual risk rather than applying uniform process regardless of consequence.

### Decision/Correction: Federated credential subject claims must match the job's actual OIDC context, not just its trigger event

Initially assumed one credential per trigger type (`ref:refs/heads/main` for push-to-main). This is incorrect once a job specifies `environment: production` — GitHub replaces the subject claim with `environment:<name>` for that job, regardless of the underlying push/PR trigger. The two are independent: the `if:` condition governs *when* the job runs; the `environment:` key governs *what subject string* is issued.

**Final federated credential set, 2 total (not 3):**
| Credential | Subject | Matches |
|---|---|---|
| `landing-zone-pull-request` | `repo:<org>/<repo>:pull_request` | The `plan` job on PRs |
| `landing-zone-prod-environment` | `repo:<org>/<repo>:environment:production` | The `apply` job (environment-gated) |

An initial `ref:refs/heads/main`-scoped credential was created, found to never match once the environment gate was added, and deleted — a stale unused credential is a minor but real audit finding, worth removing rather than leaving in place.

### Decision: Single Terraform config across all 3 subscriptions via provider aliases, not 3 parallel per-subscription pipeline jobs

Provider aliases let one `terraform apply` deploy across all 3 subscriptions in correct dependency order in a single run (e.g., Management Groups must exist before Policy assignments that reference them). Splitting into 3 parallel jobs would break this — Terraform needs the full dependency graph visible in one plan/apply to sequence cross-subscription references correctly; parallel independent applies risk race conditions (e.g., a NonProd budget referencing a Platform Action Group that doesn't exist yet).

### Decision: Terraform variables injected via `TF_VAR_*` environment variables in the pipeline, not a `-var-file`

The deployed workflow sets Terraform variables through environment variables using Terraform's native `TF_VAR_<name>` convention, sourced from a mix of GitHub Secrets (subscription IDs, alert email, OIDC object ID, tenant domain — genuinely sensitive or account-specific values) and GitHub Variables (`SHARED_RG_NAME`, `BUDGET_AMOUNT` — non-secret configuration that's still useful to keep out of hardcoded `.tf` files):

```yaml
env:
  TF_VAR_platform_subscription_id:         ${{ secrets.AZURE_PLATFORM_SUBSCRIPTION_ID }}
  TF_VAR_production_subscription_id:       ${{ secrets.AZURE_PRODUCTION_SUBSCRIPTION_ID }}
  TF_VAR_non_production_subscription_id:   ${{ secrets.AZURE_NONPROD_SUBSCRIPTION_ID }}
  TF_VAR_alert_email_address:              ${{ secrets.ALERT_EMAIL_ADDRESS }}
  TF_VAR_shared_resource_group_name:       ${{ vars.SHARED_RG_NAME }}
  TF_VAR_oidc_service_principal_object_id: ${{ secrets.OIDC_SP_OBJECT_ID }}
  TF_VAR_tenant_domain:                    ${{ secrets.TENANT_DOMAIN }}
  TF_VAR_budget_amount:                    ${{ vars.BUDGET_AMOUNT }}
```

**Why `TF_VAR_*` over a committed `terraform.tfvars` in the pipeline, or a `-var` flag list:** Terraform automatically reads any environment variable prefixed `TF_VAR_<variable_name>` and maps it to the matching declared variable — no extra CLI flags needed on the `plan`/`apply` commands themselves, and no risk of a `.tfvars` file with real values accidentally being committed or left on a runner's filesystem after the job completes (GitHub Actions runners are ephemeral, but environment variables specifically never touch disk as a file, only process memory for that job's duration). This keeps the local workflow (`terraform.tfvars`, gitignored) and the pipeline's workflow (`TF_VAR_*` from Secrets/Vars) cleanly separate, each appropriate to its own context.

**GitHub Secrets vs. GitHub Variables split:** subscription IDs, the alert email, the OIDC object ID, and the tenant domain are Secrets — not because any of them are highly sensitive on their own (see the earlier note on subscription IDs being low-risk), but because they're account/tenant-specific values with no reason to be visible in workflow run logs. `SHARED_RG_NAME` and `BUDGET_AMOUNT` are Variables instead, since they're genuinely non-sensitive configuration values that are actually useful to see in plain text in workflow logs when debugging a run.

**Note on `budget_amount` as a variable:** promoting the budget amount to a variable (rather than hardcoding `100`/`500`/`150` per environment as in the original draft) makes sense given the testing history in this project — the Platform budget was deliberately set to $2 during validation (see note above) specifically to trigger real notifications quickly; having this as a pipeline-configurable value means moving from a test amount to a production amount is a GitHub Variable change, not a code change.

`resource_group_name`, `storage_account_name`, `container_name`, `key` are non-secret and safe to commit in `backend.tf`. `subscription_id`, `tenant_id`, `client_id`, `use_oidc` are injected at `terraform init` time via `-backend-config` flags (from GitHub Secrets in the pipeline; from a gitignored `backend.hcl` locally), keeping them out of version control.

**Clarification:** the state-storage `subscription_id` is unrelated to any property of the service principal itself — service principals are tenant-level identities with no inherent subscription. This value tells Terraform which subscription to target *for this specific backend call*; the same identity is used with a different `subscription_id` when the pipeline later authenticates against Platform/Production/NonProd for actual resource deployment.

---

## Bootstrapping the Deployer Identity

### The problem

The `Landing Zone Deployer` custom role and the `mg-reale-root` management group it's scoped to are both **created by this project's own Terraform**. This means whichever identity runs the first `apply` cannot already hold that role — a genuine chicken-and-egg problem inherent to any IaC project that manages its own RBAC and MG hierarchy.

### How this is solved in enterprise practice

Most enterprise landing zone implementations (including Microsoft's own CAF reference implementation) split into two separate Terraform configurations:
- A minimal **bootstrap** config, applied once by a human using their own elevated credentials — not the pipeline's — creating only state storage, the initial management group, and the service principal.
- The **main landing zone** config, which the pipeline runs going forward using the scoped identity bootstrap created.

Enterprises typically also use Microsoft Entra Privileged Identity Management (PIM) to make any broad grant **eligible rather than standing** — activated for a short, audited window rather than permanently assigned.

### What this project does — and an early misconception corrected

The chicken-and-egg problem only applies to **whichever identity actually authenticates to run the first `apply`**. The original draft of this plan assumed the service principal (`multi-subscription-landing-zone`) would need a temporary broad `Owner` grant for this reason — but that's only true if the *service principal* is the one running that first `apply`.

In this project, the **project owner's own `az cli` session** runs the first `apply`, not the pipeline. The service principal is never authenticated during that run — it's only referenced as a *value* (`var.oidc_service_principal_object_id`), passed into the `Landing Zone Deployer` role assignment that Terraform creates *for it*. Granting the service principal a temporary `Owner` role therefore served no actual purpose: nothing in the first `apply` runs as that identity, so it never needed pre-existing access. **This was caught and removed before bootstrap — the service principal never held Owner or any broad grant at any point.**

The actual sequence:

1. State storage (resource group + storage account + container) provisioned manually in the Platform subscription, using the project owner's own `az cli` session.
2. App registration (`multi-subscription-landing-zone`) and service principal created manually. Federated credentials (`pull_request`, `environment:production`) and Graph API permission (`Group.ReadWrite.All`, admin-consented) configured — needed for the **pipeline's future runs**, not for this first `apply`.
3. Confirmed the project owner's own account already holds Owner on all 3 subscriptions, plus a directory role (Global Administrator) covering Microsoft Graph group creation — Azure RBAC roles like Owner do not, on their own, grant rights to create Entra ID groups, since that's a separate permission system.
4. `terraform init` / `plan` / `apply` run **manually, once, by the project owner, using their own identity** — creating the Management Group hierarchy, custom Policy initiative, custom RBAC roles (including `Landing Zone Deployer` itself), Entra ID groups, role assignments (including granting `Landing Zone Deployer` to the service principal), and budgets.
5. **No cleanup step is required** — since no broad grant was ever made to the service principal, there is nothing to revoke from it. The service principal's only standing access, from its very first moment of existence, is the least-privilege `Landing Zone Deployer` role at `mg-reale-root` and `Storage Blob Data Contributor` on the state storage account.
6. From this point forward, all further changes flow through the pipeline: PR → automated `plan` comment → merge to `main` → manual approval on the `production` environment → `apply`, using only the `Landing Zone Deployer` identity — which has held exactly this scope since the moment it was created, never anything broader.

This is a stronger and simpler result than the originally planned "broad grant then revoke" pattern: the human operator's own pre-existing access is what carries the bootstrap (since a human, not a machine identity, is the one running the risky first `apply`), and the pipeline identity never holds standing broad access at any point in its lifecycle — there's no revocation step to forget or skip.

### Note: Platform budget deliberately set to $2 for testing

The `platform-monthly-budget` amount was set to $2 (rather than a realistic production figure) specifically to trigger the 80%/100% notification thresholds quickly during validation, using real accumulated spend from this project's own testing activity rather than needing to artificially fabricate a threshold breach. **This is a testing-phase value, not a production recommendation** — worth resetting to a realistic figure (the original design used $100 for Platform) before treating this project as "production-ready," and noted here so the low figure in the deployed Terraform isn't mistaken for an oversight.

---

## Issues encountered during build (troubleshooting log)

| Issue | Cause | Resolution |
|---|---|---|
| Provider alias mismatch (`non_production` vs `nonprod`) causing `Provider configuration not present` on a budget resource already in state | Alias name in `.tf` files changed after a resource had already been created under the original alias name | Standardized on `non_production` across both provider declaration and all resource references |
| `terraform plan` prompting for `oidc_service_principal_object_id` | Variable referenced in Phase 3's `landing_zone_deployer` role assignment but never declared in `variables.tf` | Added the missing `variable` block; sourced the correct value via `az ad sp show --id <appId> --query id` (object ID, not app/client ID — a common mix-up) |
| `az role assignment list --assignee $APP_ID` returning empty despite assignments existing | `$APP_ID` environment variable was stale/unset from a previous shell session | Re-fetched the app ID explicitly in the current session before reusing it; confirmed by cross-checking `az role assignment list --scope <subscription>` directly, which showed the assignment existed under the correct principal |
| `azurerm_subscription_budget` resource type not found | Provider pinned to `~> 4.0`; resource was renamed to `azurerm_consumption_budget_subscription` in v4 | Renamed resource type across all 3 budget blocks; added missing `end_date` to `time_period` |
| Missing `resource_provider_registrations` behavior change | Provider v4 disabled automatic resource provider registration by default (previously automatic in v3) | Added `resource_provider_registrations = "core"` to all provider blocks |
| Planned temporary `Owner` grant to the service principal (bootstrap Steps 5/8) turned out to be unnecessary | The first `apply` is run by the project owner's own `az cli` session, not the service principal — the service principal is never authenticated during that run, only referenced as a value for a role assignment Terraform creates on its behalf | Removed the planned grant-then-revoke steps entirely; confirmed the project owner's own account already held sufficient Owner + Global Administrator rights; service principal never held any role beyond its final least-privilege `Landing Zone Deployer` assignment |
