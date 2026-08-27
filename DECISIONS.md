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

### Decision: `mg-reale-<purpose>` naming convention

Matches Microsoft CAF guidance's general `mg-<purpose>` pattern, with a company/brand prefix (`reale`) added ahead of the purpose segment. Rejected GUID-based naming (unreadable).

Management Group `name` (ID) values only need to be unique within the tenant (the Microsoft Learn documentation describes it as the "directory unique identifier") — unlike Storage Account or Key Vault names, which sit in a genuinely global, DNS-backed namespace across all of Azure. The `reale` prefix isn't needed to avoid a cross-tenant naming collision, since no such collision risk exists at this scope. It's used because it makes ownership unambiguous at a glance in the portal, and it's consistent with how the rest of this project's resources are named (e.g. `sttfstatecicd2164`, `multi-subscription-landing-zone`).

---

## Phase 2: Azure Policy

### Decision: Built-in policy definitions wherever they exist; custom only for genuine gaps

Built-ins are Microsoft-maintained and stay current as resource types and APIs evolve; a hand-written equivalent can silently go stale. Writing custom definitions for things that already exist as built-ins is generally a signal of not having checked what's available, not a demonstration of skill.

**Custom policy was still written** — one, for tag/scope drift detection (see below) — specifically to demonstrate the ability to author policy JSON where a genuine gap exists, not as the default approach.

### Decision: Bundle policies into a custom Initiative rather than assigning each individually

Assigning 4 policies individually across 3 management groups means up to 12 separate assignment resources to track. An Initiative groups them into one assignable, parameterized unit, and compliance reporting rolls up per-initiative rather than across 12 scattered states.

**Clarification on "Custom" policy_type:** the Initiative container itself is classified `Custom` because *you* assembled it — this is independent of whether the individual policies referenced inside it are built-in. Built-in initiatives (e.g., Azure Security Benchmark) were considered and rejected for this project because they bundle 200+ policies with no individual review, which undermines the goal of being able to explain every guardrail specifically.

### Decision: Differentiated policy effects per environment, not uniform `Deny`

**Note: this table reflects the original design intent. The public IP guardrail described here was later dropped from the deployed Initiative — see the superseding note below the table.**

| Policy | Platform | Production | NonProd |
|---|---|---|---|
| Deny public IPs *(later removed — see note below)* | Audit | Deny | Audit |
| Require tags | Deny | Deny | Deny |
| Allowed regions | Deny | Deny | Deny |
| Allowed VM SKUs | Deny | Deny | Deny |
| Encryption (CMK) | Audit | Audit | Audit |

Uniform `Deny` looks safest on paper but drives teams to route around governance entirely when it blocks legitimate exceptions (Platform needing a public Application Gateway; NonProd needing SKU/testing flexibility). Tags and region restriction are cheap to comply with and have no legitimate exception, so `Deny` is safe there; the public IP guardrail (before removal) and SKU restriction had real exceptions worth differentiating by environment.

**Superseded:** the public IP policy was dropped from the deployed Initiative during implementation — the final `storageEncryptionEffect` parameter also ended up Audit-only across all 3 environments after a later finding (see "the built-in storage CMK encryption policy does not support `Deny`" below) that its underlying built-in policy doesn't support a `Deny` effect at all. The Allowed VM SKUs guardrail, meanwhile, ended up `Deny` uniformly across all 3 environments in the actual deployment rather than differentiated — the live enforcement table in `README.md` reflects what's actually deployed; this table is preserved as-is to document the original reasoning, not as a current-state reference.

### Decision: Assign the Initiative once per Management Group, with different parameters, rather than once at root

Azure Policy parameters are fixed per assignment. Since effects genuinely need to differ per environment, a single root-level assignment would force identical enforcement everywhere, contradicting the differentiated-effects decision above.

### Decision: One custom policy — Environment tag must match deployment scope

Denies resources tagged `Environment=Production` when deployed under a resource group whose name contains "non-production," catching a real-world drift pattern (tag/scope mismatch) that no built-in policy covers directly.

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

MG-scope assignment means any subscription added later under that MG automatically inherits the correct access with no manual re-assignment. Dev/Test is the deliberate exception: kept at subscription scope so that if a second subscription is later added under `mg-reale-nonproduction` without vetting, Contributor access doesn't apply to it automatically.

### Decision: Entra ID groups managed as Terraform resources (`azuread_group`), not created manually

Consistency with the rest of the project — leaving group creation as an untracked manual prerequisite would break the "everything reproducible via `terraform apply`/`destroy`" premise the whole project is built on.

**Requirement this introduces:** group creation needs Microsoft Graph API application permissions (`Group.ReadWrite.All`), and looking up existing users by UPN (used for RBAC test-user group membership, see `test-users.tf`) needs a separate permission (`User.Read.All`) — both are a separate permission system from Azure RBAC. A role like Owner or Contributor on a subscription does not grant any rights over the Entra ID directory itself. This is a common point of confusion and a real gotcha documented in the CI/CD section below.

### Decision: One dedicated test user per RBAC role, managed via Terraform

Each of the 4 custom RBAC personas (Platform Infrastructure Operator, Production Support Operator, Dev/Test Contributor, Auditor) is validated using its own single-purpose test account, added to exactly one corresponding Entra ID group — never the project owner's own account, and never more than one group per test identity. Accounts are created manually in the Azure Portal, with Terraform managing group membership only via `data "azuread_user"` lookups (see `test-users.tf`).

This mirrors real separation-of-duties practice: each identity's actual access exactly matches what its role should grant, with nothing broader layered on top. See "Finding: RBAC delete-restriction test invalidated by the project owner's standing Owner access" below for why this replaced an earlier approach that added the project owner to all 4 groups, and why that approach couldn't actually validate anything.

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

### Decision: `azurerm_consumption_budget_subscription` as the budget resource type

`azurerm_consumption_budget_subscription` is the correct Terraform resource for a subscription-scoped budget, and has been the correct name since well before provider v4 (present in examples using provider `~> 3.80`). The `time_period` block's `end_date` is Optional and defaults to 10 years after `start_date` if omitted; it's set explicitly here anyway for clarity and intentional budget duration.

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

## Phase 5: CI/CD

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
2. App registration (`multi-subscription-landing-zone`) and service principal created manually. Federated credentials (`pull_request`, `environment:production`) and Graph API permissions (`Group.ReadWrite.All`, `User.Read.All`, both admin-consented) configured — needed for the **pipeline's future runs**, not for this first `apply`.
3. Confirmed the project owner's own account already holds Owner on all 3 subscriptions, plus a directory role (Global Administrator) covering Microsoft Graph group creation — Azure RBAC roles like Owner do not, on their own, grant rights to create Entra ID groups, since that's a separate permission system.
4. `terraform init` / `plan` / `apply` run **manually, once, by the project owner, using their own identity** — creating the Management Group hierarchy, custom Policy initiative, custom RBAC roles (including `Landing Zone Deployer` itself), Entra ID groups, role assignments (including granting `Landing Zone Deployer` to the service principal), and budgets.
5. **No cleanup step is required** — since no broad grant was ever made to the service principal, there is nothing to revoke from it. The service principal's only standing access, from its very first moment of existence, is the least-privilege `Landing Zone Deployer` role at `mg-reale-root` and `Storage Blob Data Contributor` on the state storage account.
6. From this point forward, all further changes flow through the pipeline: PR → automated `plan` comment → merge to `main` → manual approval on the `production` environment → `apply`, using only the `Landing Zone Deployer` identity — which has held exactly this scope since the moment it was created, never anything broader.

This is a stronger and simpler result than the originally planned "broad grant then revoke" pattern: the human operator's own pre-existing access is what carries the bootstrap (since a human, not a machine identity, is the one running the risky first `apply`), and the pipeline identity never holds standing broad access at any point in its lifecycle — there's no revocation step to forget or skip.

### Note: Platform budget deliberately set to $2 for testing

The `platform-monthly-budget` amount was set to $2 (rather than a realistic production figure) specifically to trigger the 80%/100% notification thresholds quickly during validation, using real accumulated spend from this project's own testing activity rather than needing to artificially fabricate a threshold breach. **This is a testing-phase value, not a production recommendation** — worth resetting to a realistic figure (the original design used $100 for Platform) before treating this project as "production-ready," and noted here so the low figure in the deployed Terraform isn't mistaken for an oversight.

---

## Backend & Provider Authentication: nothing inherits, every surface needs it stated explicitly

### Finding: OIDC configuration does not propagate across providers, aliases, or the backend — each needed fixing independently

The project's `provider "azurerm" {}` default block had `use_oidc`, `client_id`, and `tenant_id` set correctly from the start. Three separate failures surfaced afterward, each assumed (incorrectly) to already be covered by that one working block:

1. **Aliased providers (`platform`, `production`, `non_production`) only had `subscription_id` set.** With no `use_oidc`/`client_id`/`tenant_id` of their own, Terraform fell back to Azure CLI authentication for any resource using those aliases — which fails outright on a GitHub Actions runner with no interactive `az login` available (`could not configure AzureCli Authorizer: ... Please run 'az login'`).
2. **The `azuread` provider had no auth configuration at all** (`provider "azuread" {}`), and hit the identical CLI-fallback failure — a separate incident from #1, since `azuread` talks to Microsoft Graph, not Azure Resource Manager, and doesn't inherit anything from the `azurerm` blocks.
3. **The backend's default authentication method (`listKeys`) failed with `AuthorizationFailed`** on the OIDC service principal — the storage account's management-plane RBAC didn't include the specific `Microsoft.Storage/storageAccounts/listKeys/action` permission.

**Resolution:**
- Added `use_oidc = true`, `client_id`, and `tenant_id` to every `provider "azurerm"` block, aliased or not, and to `provider "azuread" {}`.
- Switched the backend to `use_azuread_auth = true`, replacing key-based (`listKeys`) authentication with direct Azure AD identity access to the state storage account's blob data plane. This requires `Storage Blob Data Contributor` granted explicitly to every identity that runs Terraform against this backend — the pipeline's service principal and, for local runs, the project owner's own account. Confirmed by a local `AuthorizationPermissionMismatch` once the switch was made, resolved by granting that role directly.

**The underlying lesson, worth generalizing rather than treating as three unrelated bugs:** Terraform's `backend` block, its default `provider` block, and each aliased `provider` block are independent authentication surfaces. None of them inherit configuration from one another — not from default to alias, not from `azurerm` to `azuread`, not from provider to backend. Each one either gets its auth stated explicitly or silently falls back to whatever ambient credential happens to be available (Azure CLI locally, nothing at all in CI) — which is exactly the kind of gap that works fine on a developer's laptop and fails only once it reaches an unattended pipeline.

**Also discovered during this fix:** the OIDC service principal held zero role assignments across all three subscriptions (Platform, Production, NonProd) — a gap distinct from the `use_oidc` configuration itself. Being configured to authenticate as an identity is independent of that identity actually being authorized to do anything once authenticated; both layers were missing and both needed fixing.

---

## Management Group Bootstrap: the RBAC-on-RBAC circular dependency

### The problem

`terraform apply`, run manually by the project owner (per the bootstrap sequence above), failed reading and writing policy assignments at management group scope (`mg-reale-nonproduction`, `mg-reale-root`) with `AuthorizationFailed` on `Microsoft.Authorization/policyAssignments/read` and later `roleAssignments/write` — despite the project owner holding `Owner` on all three subscriptions.

**Why Owner-on-subscription didn't cover it:** Azure RBAC scope inheritance flows downward only — parent to child, never child to parent. Subscriptions sit *below* management groups in the hierarchy; holding Owner at a subscription grants nothing at the management group above it, even though that subscription is a member of that MG. The project owner had, in effect, full rights everywhere *inside* the three subscriptions and no role of any kind — not even Reader — at `mg-reale-root` or any MG in between.

**The circular part:** the normal fix is straightforward — assign yourself a role directly at the MG scope. But doing that requires `Microsoft.Authorization/roleAssignments/write` *at that same scope*, which is precisely the permission that's missing. There is no Azure RBAC path that lets an identity grant itself the first role assignment at a scope where it currently holds none.

**Resolution:** Microsoft Entra ID's **"Elevate access"** feature exists specifically to break this circularity. Any Global Administrator (an Entra directory role, not an Azure RBAC role) can flip a one-time toggle (`Entra ID → Properties → Access management for Azure resources`, or `POST /providers/Microsoft.Authorization/elevateAccess`) that grants their own account `User Access Administrator` at the tenant root management group — the actual top of the hierarchy, above even `mg-reale-root`. From there, a normal role assignment at `mg-reale-root` scope succeeds.

**One easy-to-miss step:** elevating access changes token claims, not the current CLI session's cached token. A stale `az cli` session retried the role assignment and hit the identical error immediately after elevating, until `az logout` / `az login` refreshed the session.

**Why this is worth keeping standing, or not:** "Elevate access" grants are not self-revoking. Once the `mg-reale-root`-scoped Owner assignment was in place (the actual goal), the elevated `User Access Administrator` grant at tenant root was left as a candidate for manual removal — a broader-than-needed standing grant is exactly the kind of thing this project's own guardrails (e.g., `Landing Zone Deployer`'s explicit exclusion of `Authorization/*` writes) are designed to catch elsewhere, so leaving it unaddressed here would be inconsistent with the project's own stated principles.

**Why this is distinct from the "Bootstrapping the Deployer Identity" problem above, despite looking similar:** that section concerns the *service principal* needing no pre-existing access because it never authenticates during the first `apply`. This problem concerns the *human operator's own account* needing access at a scope where subscription-level Owner, however broad, simply doesn't reach — a genuinely different gap in the hierarchy, encountered by the identity that bootstrap already assumed would "just work."

---

## Issues encountered during build (troubleshooting log)

| Issue | Cause | Resolution |
|---|---|---|
| Provider alias mismatch (`non_production` vs `nonprod`) causing `Provider configuration not present` on a budget resource already in state | Alias name in `.tf` files changed after a resource had already been created under the original alias name | Standardized on `non_production` across both provider declaration and all resource references |
| `terraform plan` prompting for `oidc_service_principal_object_id` | Variable referenced in Phase 3's `landing_zone_deployer` role assignment but never declared in `variables.tf` | Added the missing `variable` block; sourced the correct value via `az ad sp show --id <appId> --query id` (object ID, not app/client ID — a common mix-up) |
| `az role assignment list --assignee $APP_ID` returning empty despite assignments existing | `$APP_ID` environment variable was stale/unset from a previous shell session | Re-fetched the app ID explicitly in the current session before reusing it; confirmed by cross-checking `az role assignment list --scope <subscription>` directly, which showed the assignment existed under the correct principal |
| `terraform init` hung indefinitely in GitHub Actions (multi-hour, no error) | `backend.tf`'s `backend "azurerm" {}` block was empty by design (values meant to come from `-backend-config`), but the pipeline's `init` step only passed the dynamic/secret values (`subscription_id`, `tenant_id`, `client_id`, `use_oidc`) via inline flags — the static values (`resource_group_name`, `storage_account_name`, `container_name`, `key`) were never supplied, since they live in a gitignored, pipeline-inaccessible `backend.hcl`. Terraform responded by interactively prompting for each missing value, one at a time — which hangs forever in a non-interactive CI runner rather than failing fast | Moved the static, non-secret backend values directly into the committed `backend.tf`; added `-input=false` to every Terraform command in the pipeline as a safety net so any future missing-value scenario fails immediately with a clear error instead of hanging silently |
| Pipeline `plan` showed `azurerm_role_assignment.landing_zone_deployer` needing replacement, with `principal_id` changing despite the `.tf` code being unchanged | `var.oidc_service_principal_object_id` resolves from different sources depending on who runs `apply` — local `terraform.tfvars` for manual runs, the `OIDC_SP_OBJECT_ID` GitHub Secret for pipeline runs. The GitHub Secret held a stale/incorrect value (likely from an earlier round of app-registration troubleshooting where client ID and object ID were being distinguished), while the local `.tfvars` held the correct value already recorded in state | Confirmed the correct object ID via `az ad sp list`, corrected the GitHub Secret to match. **This also served as unplanned but genuine proof that the self-elevation guardrail works**: when the pipeline attempted the (incorrect, drift-caused) replace, `Landing Zone Deployer`'s exclusion of `Microsoft.Authorization/roleAssignments/delete` blocked it outright — the pipeline identity could not modify its own role assignment even when Terraform itself was instructing it to. The fix required a human, running locally with standing access, to correct the underlying data (the secret value) rather than the pipeline being able to push through an RBAC change of any kind, correct or not |
| Wrong resource type used initially for budgets | `azurerm_subscription_budget` isn't a valid resource name; the correct type is `azurerm_consumption_budget_subscription` | Corrected the resource type across all 3 budget blocks; added an explicit `end_date` to `time_period` for clarity |
| `resource_provider_registrations` set to `"core"` | Provider v4.x defaults to `legacy` (a broad, curated set of Resource Providers auto-registered on init, carried forward from v3 behavior). Setting `resource_provider_registrations = "core"` narrows this to a smaller, more minimal set rather than accepting the broader default | Added `resource_provider_registrations = "core"` to all provider blocks as a deliberate scoping choice |
| Planned temporary `Owner` grant to the service principal (bootstrap Steps 5/8) turned out to be unnecessary | The first `apply` is run by the project owner's own `az cli` session, not the service principal — the service principal is never authenticated during that run, only referenced as a value for a role assignment Terraform creates on its behalf | Removed the planned grant-then-revoke steps entirely; confirmed the project owner's own account already held sufficient Owner + Global Administrator rights; service principal never held any role beyond its final least-privilege `Landing Zone Deployer` assignment |
