# AAP 2.7 Configuration as Code -- Platform Configuration

This repository contains the Configuration as Code (CaC) definitions for the **platform-level** resources of Red Hat Ansible Automation Platform 2.7. It manages organizations, RBAC, authentication, shared Execution Environments, custom credential types, instance groups, and Hub configuration across three AAP clusters (dev, staging, prod).

**This repo is owned and maintained by the Platform Admin team.** Individual team configurations are maintained in separate per-team repositories (see [Team Config Repos](#team-config-repos)).

## Governance Model

### Organization Topology

Each tenant team gets **one AAP organization** providing full resource isolation. Organizations are the strongest boundary in AAP 2.7 -- inventories, credentials, projects, job templates, and workflows are all scoped to an org. Cross-team data sharing is not enabled by default but can be granted on specific resources via platform-managed sharing definitions (see [Cross-Org Resource Sharing](#cross-org-resource-sharing)).

```
AAP Cluster (per environment)
├── Global EEs (no org)     ← Visible to all orgs (ee-supported, ee-minimal)
├── Org: Platform           ← Platform team admin workspace
├── Org: Team-Alpha         ← Isolated tenant (may have team-exclusive EEs)
├── Org: Team-Bravo         ← Isolated tenant
└── Org: Team-...N          ← Isolated tenant
```

### RBAC Model

Admin roles are granted directly to LDAP users via authenticator maps (the AAP 2.7 Gateway API blocks assigning global roles and Organization Member permissions to teams). Operator teams receive `Organization Execute` via team role assignment.

**Per-team RBAC:**

| LDAP Group | Role | Mechanism |
|---|---|---|
| `aap-<team>-admins` | Organization Admin | Authenticator map (`map_type: organization`) |
| `aap-<team>-operators` | Organization Execute | AAP team + `role_team_assignment` |

Team admins can create additional **sub-teams** (e.g., developers, QA, viewers) with fine-grained role assignments within their org using their team CaC repo. See the team template README for details.

Optional sub-teams can be pre-provisioned via the `custom_teams` field in the team definition file. The onboarding playbook creates the sub-teams, maps LDAP groups, and assigns org-level roles (via `org_role`). Resource-scoped role assignments (on specific projects, job templates, inventories) are handled in the team's own CaC repo.

**Platform RBAC:**

| LDAP Group | Role | Mechanism |
|---|---|---|
| `aap-platform-admins` | System Administrator | Authenticator map (`is_superuser`) |
| `aap-platform-operators` | Organization Execute | AAP team + `role_team_assignment` |

### What the Platform Team Manages

- Execution Environments -- global (no org, visible to all) and team-exclusive (org-scoped)
- EE builds via the `aap-ee-builds` repo (see design doc Section 8)
- Custom Credential Types (system-level, available to all orgs)
- Instance / Container Groups (assigned to team orgs)
- LDAP authenticator and group-to-team mappings (including sub-team maps)
- Hub content (collections, EE registries, namespaces)
- Team onboarding / offboarding

### What Each Team Manages (in their own repo)

- Sub-teams and role assignments within their org
- Inventories
- Credentials
- Projects (Git repos with playbooks)
- Job Templates
- Workflow Job Templates
- Schedules

## Hub Collection Management

The private Automation Hub is the single source of truth for all Ansible collections consumed by CaC repos. Collections are synced from Red Hat and community sources into Hub, and all AAP organizations resolve collections from Hub during project sync.

### Hub Remotes (Upstream Sync)

Which collections are synced from external sources is controlled entirely by `config/all/hub_collection_remote.yml`. Each remote has a `requirements` filter (allowlist) and a `sync` flag:

| Remote | Collections Synced | `sync` |
|---|---|---|
| `rh-certified` | `ansible.controller`, `ansible.platform`, `ansible.hub`, `ansible.eda` | `true` |
| `validated` | `infra.aap_configuration` | `true` |
| `community` | (none by default) | `false` |

Remote sync requires a `redhat_api_token` (offline token from console.redhat.com) in each environment's `secrets.yml`. The `apply_config.yml` playbook triggers a sync for remotes with `sync: true` and a non-empty `requirements` list after dispatch runs.

**Adding a CaC collection**: edit `hub_collection_remote.yml` only -- add the collection name to the appropriate remote's `requirements` list. The sync playbook reads directly from this config (no duplication in the playbook).

**Standalone sync** (without running full dispatch):

```bash
# Sync all enabled remotes
ansible-playbook -i inventory/inventory_dev.yml -l dev playbooks/sync_hub_collections.yml --vault-password-file=../.vault-pass

# Sync only specific remotes
ansible-playbook -i inventory/inventory_dev.yml -l dev playbooks/sync_hub_collections.yml --vault-password-file=../.vault-pass \
  -e 'hub_sync_remotes=["community"]'
```

A **Sync Hub Collections** JT is also registered in Controller for on-demand use, with `platform-gateway-cred` and `platform-secrets` credentials attached.

**Requesting an upstream collection** (team process):

1. Team PRs to this repo: add the collection to the remote's `requirements` in `hub_collection_remote.yml`.
2. Platform reviews (licensing, security).
3. Merge. Run `sync_hub_collections.yml` or let the next `apply_config` pick it up.
4. Team adds the collection to their `collections/requirements.yml`.

### Publishing Custom Collections

Teams can contribute custom collections for internal consumption via the `aap-hub-collections` repo. All custom collections share a single configurable namespace (default: `hig`, set via `hub_custom_collection_namespace` in `config/{env}/_commons.yml`).

**Process**: Team PRs their collection to `aap-hub-collections` -> platform reviews -> merge -> CI builds and publishes to Hub's `staging` repo -> approved into `published`.

See the [`aap-hub-collections` README](../aap-hub-collections/README.md) for the full contribution guide, CI pipeline, and manual publish instructions.

**Credentials for publishing**: The `aap-hub-collections` CI pipeline reuses the same Jenkins `aap-hub-credentials` credential (platform admin account) used by this repo. No dedicated Hub service account is needed. See `hub_group_roles.yml` for least-privilege upgrade options if required later.

### Hub Repositories

| Repository | Pipeline | Purpose |
|---|---|---|
| `rh-certified` | `approved` | Red Hat certified collections (synced from console.redhat.com) |
| `validated` | `approved` | Red Hat validated collections |
| `community` | `approved` | Community content (on demand) |
| `staging` | `staging` | Upload landing zone for custom collections |
| `published` | `approved` | Approved custom collections for consumption |

`staging` and `published` are Hub defaults but are declared in `hub_collection_repository.yml` to guarantee they exist.

### Hub Galaxy Credentials

Three platform-managed Galaxy credentials are attached to every organization (Platform and all team orgs), one per Hub repository:

| Credential | Hub Repository | Collections |
|---|---|---|
| `hub-galaxy-rh-certified` | `rh-certified` | `ansible.controller`, `ansible.platform`, `ansible.hub`, `ansible.eda` |
| `hub-galaxy-validated` | `validated` | `infra.aap_configuration` |
| `hub-galaxy-published` | `published` | Internally published custom collections |

Controller tries credentials in order during project sync, so collections from all three repositories are resolved.

**Token lifecycle**: The API token is a Gateway PAT created on the first `apply_config.yml` run. Subsequent runs skip token creation if the credentials already exist. A scheduled job template (`Refresh Hub Galaxy Token`) handles token rotation, with `platform-gateway-cred` attached for API access. The rotation interval is derived from `hub_galaxy_token_expire_seconds` in `config/{env}/_commons.yml` (default: 1 year). See the design doc Section 2.4.2a for details.

**Prerequisite**: `platform_cac_repo_url` in `config/{env}/_commons.yml` must point to a real, reachable git repo. The `Refresh Hub Galaxy Token` JT and its schedule depend on the `aap-platform-config` Controller project being synced.

### CLI Collection Install

For local testing, `ansible.cfg` lists three Hub Galaxy servers. Authenticate via env vars:

```bash
export ANSIBLE_GALAXY_SERVER_HUB_RH_CERTIFIED_USERNAME="admin"
export ANSIBLE_GALAXY_SERVER_HUB_RH_CERTIFIED_PASSWORD="xxx"
export ANSIBLE_GALAXY_SERVER_HUB_VALIDATED_USERNAME="admin"
export ANSIBLE_GALAXY_SERVER_HUB_VALIDATED_PASSWORD="xxx"
export ANSIBLE_GALAXY_SERVER_HUB_PUBLISHED_USERNAME="admin"
export ANSIBLE_GALAXY_SERVER_HUB_PUBLISHED_PASSWORD="xxx"
ansible-galaxy collection install -r collections/requirements.yml
```

### Jenkins

The Jenkinsfile injects Hub credentials from a `usernamePassword` Jenkins credential (`aap-hub-credentials`) during the "Install Collections" stage.

## Execution Environments

EEs are built in the separate `aap-ee-builds` repo and registered here in `controller_execution_environments.yml`.

**Scope enforcement** is via the `organization` field:
- **Global EEs**: `organization` omitted -- visible to all orgs
- **Team-exclusive EEs**: `organization` set to a specific team org -- only that org can use it

## Directory Structure

```
ansible.cfg
.ansible-lint
.yamllint
.pre-commit-config.yaml
collections/
└── requirements.yml
inventory/
├── inventory_dev.yml
├── inventory_staging.yml
└── inventory_prod.yml
config/
├── all/                          # Applied to ALL environments
│   ├── aap_organizations.yml
│   ├── aap_teams.yml
│   ├── gateway_authenticators.yml
│   ├── gateway_authenticator_maps.yml
│   ├── gateway_role_definitions.yml
│   ├── gateway_role_team_assignments.yml
│   ├── gateway_settings.yml
│   ├── controller_credential_types.yml
│   ├── controller_execution_environments.yml  # Global + team-exclusive EEs
│   ├── controller_instance_groups.yml
│   ├── controller_credentials.yml
│   ├── controller_projects.yml
│   ├── controller_job_templates.yml
│   ├── hub_collection_remote.yml
│   ├── hub_collection_repository.yml
│   ├── hub_namespace.yml
│   └── hub_group_roles.yml
├── dev/
│   ├── _commons.yml             # Cleartext tunable vars (non-dispatch, _ prefix)
│   └── secrets.yml
├── staging/
│   ├── _commons.yml
│   └── secrets.yml
└── prod/
    ├── _commons.yml
    └── secrets.yml
team_definitions/
├── team-alpha.yml                # One file per tenant team
└── team-bravo.yml
sharing_definitions/
├── team-bravo-from-team-alpha.yml  # Cross-org sharing grants
└── *.yml.sample                    # Template for new sharing definitions
playbooks/
├── apply_config.yml
├── team_onboarding.yml
├── _team_onboard_tasks.yml
├── team_offboarding.yml
├── apply_sharing.yml              # Cross-org sharing (module-based)
├── apply_sharing_api.yml          # Cross-org sharing (API-based fallback)
├── _apply_sharing_module_tasks.yml
├── _apply_sharing_api_tasks.yml
├── _apply_sharing_api_grant.yml
├── rotate_svc_credentials.yml    # Rotate all/single team service account passwords
├── _rotate_svc_credential.yml
├── sync_hub_collections.yml      # Standalone upstream collection sync (no dispatch)
├── refresh_hub_galaxy_token.yml  # Scheduled token refresh for Hub Galaxy credentials
├── _hub_galaxy_credential_tasks.yml  # Shared: token + credential management
└── _hub_sync_tasks.yml           # Hub remote upsert + sync (data-driven from config)
Jenkinsfile
```

## How It Works

### Variable Merging (`config/all/` + `config/<env>/`)

This repo follows the pattern from [redhat-cop/aap_configuration_template](https://github.com/redhat-cop/aap_configuration_template):

1. Variables in `config/all/` use the `_all` suffix (e.g., `aap_organizations_all`)
2. Variables in `config/<env>/` use the `_<env>` suffix (e.g., `controller_credentials_dev`)
3. The `infra.aap_configuration.dispatch` role merges both lists automatically when `dispatch_include_wildcard_vars: true`
4. Env-specific items are **additive**, not replacements

**File convention**:
- `config/all/*.yml` -- dispatch resource lists only (`_all` suffixed variables)
- `config/<env>/secrets.yml` -- vault-encrypted secrets and sensitive env-specific vars
- `config/<env>/_commons.yml` -- cleartext tunable vars (e.g., `platform_cac_repo_url`, `hub_galaxy_token_expire_seconds`, `hub_custom_collection_namespace`). These are plain Ansible variables consumed by Jinja2 templates, not dispatch-managed resources. The `_` prefix distinguishes non-dispatch files from dispatch resource files

### Applying Configuration

**Platform config** is applied via Jenkins:

```bash
ansible-playbook -i inventory/inventory_dev.yml -l dev playbooks/apply_config.yml --vault-password-file=...
```

**Team config** is applied via AAP project sync + job template within each team's org (self-service).

### Environment Promotion

- **dev**: Auto-applied on merge to `main`
- **staging**: Manual trigger
- **prod**: Manual approval gate

## Team Onboarding

1. Team creates required LDAP groups and clones `aap-team-template` into their own `aap-team-<name>-config` repo
2. Team submits a PR adding `team_definitions/<team-name>.yml` (must include `cac_repo_url` pointing to the live repo)
3. Platform team reviews the PR (verifies repo URL is reachable, LDAP groups correct)
4. Platform merges and runs `team_onboarding.yml` against each cluster (the playbook is idempotent -- safe to re-run):
   ```bash
   ansible-playbook -i inventory/inventory_dev.yml -l dev playbooks/team_onboarding.yml --vault-password-file=../.vault-pass
   ansible-playbook -i inventory/inventory_staging.yml -l staging playbooks/team_onboarding.yml --vault-password-file=../.vault-pass
   ansible-playbook -i inventory/inventory_prod.yml -l prod playbooks/team_onboarding.yml --vault-password-file=../.vault-pass
   ```
5. Playbook validates repo is reachable -> provisions org, RBAC, svc account, gateway credential, vault credential, project, and JT
6. Team updates the vault credential password in AAP UI when they start using vault-encrypted secrets (see team template README)

> **Pre-flight check**: The playbook validates that `cac_repo_url` is reachable before creating any resources. If the repo doesn't exist, the playbook fails fast with a clear error message directing the team to create the repo first.

> **Vault credentials**: A `<team>-vault-password` credential (type: Vault) is auto-provisioned during onboarding with a random placeholder password and attached to the team's JT. Teams that use `ansible-vault encrypt_string` update the password in AAP UI. The credential is created with `update_secrets: false`, so re-running onboarding never overwrites a team's updated password.

### Service Account Provisioning

The onboarding playbook automatically creates a local service account (`svc-<team>-cac`) with:
- Organization Admin scoped to the team's org
- An auto-generated random password (never persisted to files)
- A gateway credential (type: "AAP CaC Credential") stored in the **Platform org** and attached to the `<team> - Apply Team Config` JT. The custom type injects both `CONTROLLER_*` / `AAP_*` env vars **and** `extra_vars` (`aap_hostname`, `aap_username`, `aap_password`, `aap_validate_certs`) so dispatch works with both `ansible.controller` and `ansible.platform` modules and playbooks can reference credentials as Ansible variables
- A vault credential (`<team>-vault-password`, type: Vault) in the **team's org** with a random placeholder password, attached to the JT. Team admins (Organization Admin) can update the password directly. Cascade-deleted when the org is removed during offboarding

The credential is owned by the Platform org so team admins cannot see, manage, or reuse it. AAP never exposes credential secrets via the API.

**Re-run safety**: On re-runs, existing service accounts are not modified (`update_secrets: false`) and credential creation is skipped -- this keeps the user and credential passwords in sync.

**Troubleshooting 401 on team CaC**: If a team's CaC JT fails with 401, the service account password and credential are likely out of sync. Delete the `svc-<team>-cac` user in AAP and re-run onboarding to recreate both with a matching password.

### Credential Rotation

Rotate service account passwords for all teams (or a single team) using:

```bash
# All teams in dev
ansible-playbook -i inventory/inventory_dev.yml playbooks/rotate_svc_credentials.yml --vault-password-file=../.vault-pass

# Single team in dev
ansible-playbook -i inventory/inventory_dev.yml playbooks/rotate_svc_credentials.yml -e target_team=team-bravo --vault-password-file=../.vault-pass
```

Run against each env's inventory to rotate in that environment. Can be scheduled (e.g., quarterly).

### Team Offboarding

Remove a team by running the offboarding playbook against each cluster. Only `team_name` is required -- `org_display_name` and all resource names are derived from the team definition file:

```bash
ansible-playbook -i inventory/inventory_dev.yml -l dev playbooks/team_offboarding.yml -e team_name=team-bravo --vault-password-file=../.vault-pass
```

The playbook deletes all resources created during onboarding in reverse order:

1. **Custom sub-team authenticator maps** (for any sub-teams defined in `custom_teams`)
2. **Admin and operator authenticator maps**
3. **Gateway credential** (`<team>-gateway-cred`) from the Platform org
4. **Service account** (`svc-<team>-cac`)
5. **Organization** (cascades: JT, project, inventory, vault credential, teams)

> **Sharing definitions**: The playbook automatically scans `sharing_definitions/` and warns about any files referencing the offboarded team (as owner or consumer). These files should be removed via a follow-up PR -- they are Git-managed and not deleted automatically.

### Custom Credential Types and Platform JT Credentials

Two custom credential types support non-interactive execution:

| Credential Type | Injected As | Purpose |
|---|---|---|
| **AAP CaC Credential** | `env` (`CONTROLLER_*`, `AAP_*`) + `extra_vars` (`aap_hostname`, `aap_username`, `aap_password`, `aap_validate_certs`, `_cred_injected`) | API authentication for CaC playbooks |
| **Platform Secrets** | `extra_vars` (`redhat_api_token`) | Red Hat API token for Hub remote sync |

Platform-managed credentials:

| Credential | Type | Attached To |
|---|---|---|
| `platform-gateway-cred` | AAP CaC Credential | Refresh Hub Galaxy Token, Sync Hub Collections |
| `platform-secrets` | Platform Secrets | Sync Hub Collections |

The `_cred_injected` sentinel (injected as `extra_vars: true`) allows playbooks to detect JT mode and conditionally skip loading `secrets.yml` via `include_vars` (vault-encrypted secrets are unnecessary when credentials inject the required values directly).

### Transitioning to an External Secrets Manager

The current design generates passwords inline and stores them only in AAP Credential objects. To migrate to an external secrets manager (HashiCorp Vault, CyberArk, etc.):

1. Replace the `lookup('password', '/dev/null ...')` call in `_team_onboard_tasks.yml` and `_rotate_svc_credential.yml` with your secrets manager lookup plugin (e.g., `lookup('hashi_vault', 'secret/data/aap/svc-{{ _team.team_name }}-cac')`)
2. No other task structure changes are needed -- the user creation, role assignment, and credential update tasks remain identical
3. The external secrets manager becomes the source of truth for password storage and audit logging

### Team Definition File

The team definition supports an optional `metadata` block for governance tracking and an optional `custom_teams` field for sub-teams with LDAP mapping and an org-level role:

```yaml
team_name: "team-bravo"
org_display_name: "Team-Bravo"
description: "Bravo team automation resources"

metadata:                                     # optional but recommended
  contacts:
    - name: "Jane Doe"
      email: "jdoe@example.com"
      role: "Technical Lead"
    - name: "John Smith"
      email: "jsmith@example.com"
      role: "Product Owner"
  cost_center: "CC-67890"
  business_unit: "Engineering"
  slack_channel: "#team-bravo-aap"
  jira_project: "BRAVO"
  onboarded_date: "2026-08-15"
  tags: [automation, infrastructure]

ldap_groups:
  admins: "aap-team-bravo-admins"
  operators: "aap-team-bravo-operators"

custom_teams:                                 # optional
  - name: "team-bravo-devs"
    ldap_group: "aap-team-bravo-devs"
    org_role: "Organization Execute"          # org-level role applied at onboarding
    # Resource-scoped roles (e.g., "JobTemplate Execute" on specific JTs)
    # go in the team CaC repo: config/all/gateway_role_team_assignments.yml

instance_group: "default"                     # optional; defaults to "default"
cac_repo_url: "https://github.com/example-aap/aap-team-bravo-config.git"
```

**Mandatory fields**: `team_name`, `org_display_name`, `ldap_groups.admins`, `ldap_groups.operators`, `cac_repo_url`

**Optional fields**: `instance_group` (default: "default"), `description`, `custom_teams`, `metadata`

See `team_definitions/` for complete examples.

## Team Config Repos

Each team's CaC repo follows the same `config/all` + `config/<env>` pattern with the `dispatch` role, but only contains team-scoped resources (including optional sub-team and role assignment definitions). The template repo is: `aap-team-template`.

## Cross-Org Resource Sharing

By default, organizations are fully isolated -- resources in one org are invisible to other orgs. However, AAP 2.7's resource-level RBAC allows the platform team to grant specific cross-org access via sharing definitions.

### How It Works

1. A team submits a PR adding `sharing_definitions/<consumer>-from-<owner>.yml`
2. Platform team reviews and merges
3. Platform runs the sharing playbook against each environment

The consumer team gains access only to the specific shared resources (not the entire owner org), unless an org-level role is granted.

### Sharing Definition Format

```yaml
# sharing_definitions/team-bravo-from-team-alpha.yml
sharing_name: "team-bravo-from-team-alpha"
owner_org: "Team-Alpha"
consumer_team: "team-bravo-operators"
grants:
  - resource_name: "deploy-shared-infra"
    resource_type: job_templates
    role_definition: "JobTemplate Execute"
  - resource_name: "shared-deploy-credential"
    resource_type: credentials
    role_definition: "Credential Use"
state: present
```

**Fields:**

| Field | Purpose |
|-------|---------|
| `sharing_name` | Unique identifier for this sharing relationship |
| `owner_org` | Organization owning the shared resources (used to resolve names to IDs) |
| `consumer_team` | AAP team receiving access (must already exist) |
| `grants[].resource_name` | Name of the resource in the owner org (or the org name for org-level roles) |
| `grants[].resource_type` | `job_templates`, `workflows`, `credentials`, `inventories`, `projects`, or `organizations` |
| `grants[].role_definition` | Role to grant (see sharing definition file for full list of allowed values) |
| `state` | `present` to create grants; `absent` to revoke |

**Resource-level roles** (grant access to a single resource):
`JobTemplate Execute`, `JobTemplate Admin`, `WorkflowJobTemplate Execute`, `Credential Use`, `Credential Admin`, `Inventory Use`, `Inventory Admin`, `Project Use`, `Project Admin`

**Org-level roles** (grant access to ALL resources in the target org):
`Organization Execute`, `Organization Audit`, `Organization Inventory Admin`, `Organization Credential Admin`, `Organization Project Admin`, `Organization JobTemplate Admin`

> **Warning**: Org-level roles grant access to ALL current AND future resources of the granted type in the target org. If the owner team later adds a sensitive job template, the consumer team automatically inherits access. Use resource-level grants for fine-grained control.

**Custom roles** (view-only, requires creation via `config/all/gateway_role_definitions.yml` first):
`JobTemplate View`, `Credential View`, `Inventory View`, `Project View` -- see `gateway_role_definitions.yml` for examples and full permission reference.

### Applying Sharing

Two implementations are available:

```bash
# API-based (recommended for cross-org sharing -- explicitly resolves resource IDs)
ansible-playbook -i inventory/inventory_dev.yml -l dev playbooks/apply_sharing_api.yml --vault-password-file=../.vault-pass

# Module-based (same-org only -- uses ansible.platform.role_team_assignment)
# WARNING: This causes a 500 error for cross-org assignments on aap-operator.v2.7.0-0.1785438991.
# The module sends the resource name instead of its ID when the resource is in a different org.
ansible-playbook -i inventory/inventory_dev.yml -l dev playbooks/apply_sharing.yml --vault-password-file=../.vault-pass
```

Run against each environment's inventory to apply sharing in that environment.

### Revoking Sharing

Set `state: absent` in the sharing definition and re-run the playbook. The file is preserved in Git history for audit purposes.

### Constraints

- Only System Administrators can create cross-org grants (the playbook runs with platform admin credentials)
- The consumer team must already exist (created via team onboarding)
- The shared resources must already exist in the owner org
- Shared credentials can be *used* but secrets are never exposed (`$encrypted$`)
- `Organization Admin` and `Organization Member` cannot be assigned to teams (API restriction)
- When offboarding a team, the playbook warns about stale sharing definitions -- remove them via PR

## Related Repos

| Repository | Purpose |
|---|---|
| `aap-platform-config` | This repo -- platform-level CaC |
| `aap-hub-collections` | Custom Ansible collections for internal Hub publishing |
| `aap-ee-builds` | EE build definitions (ansible-builder) and CI/CD |
| `aap-team-template` | Template for per-team CaC repos |
| `aap-team-<name>-config` | Per-team CaC (forked from template) |

## Prerequisites

- AAP 2.7 with platform gateway accessible
- LDAP authentication configured
- Ansible collections installed (see `collections/requirements.yml`)
- `redhat_api_token` in each environment's `secrets.yml` (offline token from [console.redhat.com](https://console.redhat.com/ansible/automation-hub/token) for Hub remote sync)
- Jenkins with access to AAP gateway endpoints
- Jenkins `aap-hub-credentials` credential (usernamePassword) for collection install from Hub
- Ansible Vault password for decrypting secrets

## References

- [AAP 2.7 Documentation](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.7)
- [CaC with ansible.platform collection](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.7/configure-about_configuration_as_code)
- [Manage access with RBAC](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.7/secure-assembly_gw_managing_access)
- [ansible.platform collection modules](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.7/configure-ansible_platform_collection_modules)
- [redhat-cop/aap_configuration_template](https://github.com/redhat-cop/aap_configuration_template)
- [infra.aap_configuration](https://github.com/redhat-cop/infra.aap_configuration)
