# AAP 2.7 Configuration as Code

Multi-tenant governance model and Configuration as Code (CaC) for Red Hat Ansible Automation Platform 2.7, supporting 100+ teams with strict isolation across three environments (dev, staging, prod).

## Repository Layout

```
.
├── aap-platform-config/    # Platform-level CaC (owned by platform team)
├── aap-ee-builds/          # Execution Environment build definitions and CI pipeline
├── team-template/           # Template repo for tenant teams
└── docs/                    # Design documentation
```

### [aap-ee-builds/](aap-ee-builds/)

Execution Environment build definitions managed by the platform team. Contains `ansible-builder` (v3) definitions for all EE images used across the AAP clusters:

- `global/` -- EEs available to all organizations (no `organization` field in Controller)
- `teams/<team-name>/` -- EEs exclusive to a specific team org
- Jenkinsfile with CI/CD pipeline: lint, `ansible-builder build`, and registry push
- Changed-EE detection via git diff (only modified EEs are rebuilt)

Teams request new EEs by submitting PRs to this repo. See [aap-ee-builds/README.md](aap-ee-builds/README.md) for the full workflow.

### [aap-platform-config/](aap-platform-config/)

Platform-level configuration managed by the platform admin team. Contains:

- Organizations, teams, and RBAC definitions
- LDAP authenticator and group-to-team mappings
- Execution Environments -- global (visible to all orgs) and team-exclusive (org-scoped)
- Custom credential types and instance/container group assignments
- Hub configuration (remotes, repositories, namespaces)
- Team onboarding/offboarding playbooks (including optional sub-team provisioning)
- Jenkins pipeline for env promotion (dev -> staging -> prod)

### [team-template/](team-template/)

Template repository that each tenant team forks to create their own `aap-team-<name>-config` repo. Contains scaffolding for:

- Sub-teams and fine-grained role assignments within the team's org
- Inventories, credentials, projects
- Job templates, workflow job templates, schedules
- Per-environment overrides and secrets

## Governance Model

- **1 AAP organization per team** for full resource isolation
- **LDAP-based RBAC**: admin roles (System Administrator, Organization Admin) granted via authenticator maps; operator teams get Organization Execute via team role assignment
- **Team-admin self-service RBAC**: team admins can create sub-teams (developers, QA, viewers) with fine-grained role assignments via CaC
- **LDAP group mapping** for automatic role/team assignment on login
- **Platform team** manages shared global resources (EEs, credential types, instance groups, Hub)
- **EE scope enforcement**: global EEs visible to all, team-exclusive EEs scoped to specific orgs
- **No cross-team data sharing** -- organizations are the isolation boundary

## How Teams Are Onboarded

1. Team creates required LDAP groups and clones `team-template/` into their own `aap-team-<name>-config` repo
2. Team adds a definition file to `aap-platform-config/team_definitions/`
3. Platform team reviews and merges the PR
4. Platform team runs the onboarding playbook (once per cluster) which provisions the org, RBAC, service account, project, and JT. The playbook is idempotent and can be re-run safely.
5. Team manages their config via PRs. A vault credential is auto-provisioned during onboarding -- teams update the password in AAP UI when they start using vault-encrypted secrets

See [aap-platform-config/README.md](aap-platform-config/README.md) for full details.
