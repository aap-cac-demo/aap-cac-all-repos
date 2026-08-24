# AAP 2.7 Configuration as Code -- Team Template

This is the template repository for tenant team CaC configurations. Fork this repo to create your team's `aap-team-<name>-config` repository.

## What This Repo Manages

Your team's CaC repo manages the following resources within your AAP organization:

- **Sub-teams & RBAC** -- additional teams with fine-grained role assignments within your org
- **Inventories** -- target hosts for automation
- **Credentials** -- authentication for remote systems and services
- **Projects** -- Git repos containing your playbooks
- **Job Templates** -- standardized automation tasks
- **Workflow Job Templates** -- multi-step automation orchestration
- **Schedules** -- recurring automation runs

## Structure

```
aap-team-<name>-config/
├── config/
│   ├── all/                          # Resources for ALL environments
│   │   ├── aap_teams.yml                      # Sub-teams within your org
│   │   ├── gateway_role_team_assignments.yml  # Role assignments for sub-teams
│   │   ├── controller_inventories.yml
│   │   ├── controller_credentials.yml
│   │   ├── controller_projects.yml
│   │   ├── controller_job_templates.yml
│   │   ├── controller_workflow_job_templates.yml
│   │   └── controller_schedules.yml
│   ├── dev/
│   │   ├── controller_inventories.yml
│   │   └── secrets.yml
│   ├── staging/
│   │   ├── controller_inventories.yml
│   │   └── secrets.yml
│   └── prod/
│       ├── controller_inventories.yml
│       └── secrets.yml
├── inventory/
│   ├── inventory_dev.yml
│   ├── inventory_staging.yml
│   └── inventory_prod.yml
├── playbooks/
│   └── apply_team_config.yml
└── collections/
    └── requirements.yml
```

## How It Works

1. Define your resources in `config/all/*.yml` (applied to all environments)
2. Add environment-specific overrides in `config/<env>/*.yml`
3. Variables use the `_all` / `_<env>` suffix convention:
   - `controller_inventories_all` in `config/all/`
   - `controller_inventories_dev` in `config/dev/`
   - The dispatch role merges both lists automatically
4. Secrets go in `config/<env>/secrets.yml` using `ansible-vault encrypt_string`

## Sub-Teams & Fine-Grained RBAC

Your team admins (who receive Organization Admin via LDAP authenticator map) can create additional sub-teams and assign roles within your org -- no platform team involvement needed.

### Creating Sub-Teams

Define sub-teams in `config/all/aap_teams.yml`:

```yaml
aap_teams_all:
  - name: "team-alpha-developers"
    organization: "Team-Alpha"
    state: present
  - name: "team-alpha-qa"
    organization: "Team-Alpha"
    state: present
```

### Assigning Roles to Sub-Teams

Define role assignments in `config/all/gateway_role_team_assignments.yml`. Each sub-team can have multiple role assignments.

> **Note**: If your sub-teams were pre-provisioned during onboarding (via `custom_teams` in your team definition), the platform may have already assigned an org-level role (e.g., `Organization Execute`). Use this file to add any additional resource-scoped role assignments that target specific projects, job templates, inventories, or other resources within your org.

```yaml
gateway_role_team_assignments_all:
  # Developers: org-wide execute + admin on a specific project
  - team: team-alpha-developers
    role_definition: Organization Execute
    assignment_objects:
      - name: Team-Alpha
        type: organizations
    state: present
  - team: team-alpha-developers
    role_definition: Project Admin
    assignment_objects:
      - name: app-playbooks
        type: projects
    state: present

  # QA: org-wide execute + manage QA inventories
  - team: team-alpha-qa
    role_definition: Inventory Admin
    assignment_objects:
      - name: qa-servers
        type: inventories
    state: present
```

### LDAP Mapping for Sub-Teams

Authenticator maps are system-level and can only be created by the platform team. Two options:

1. **Platform-assisted**: Add sub-team LDAP groups to your `team_definitions/<team>.yml` via the `custom_teams` field. The platform onboarding playbook creates the sub-teams, LDAP authenticator maps, and optionally assigns an org-level role (e.g., `Organization Execute`). Any **resource-scoped** role assignments (e.g., `Project Admin` on a specific project, `Job Template Execute` on a specific JT) must be defined here in your team CaC repo under `config/all/gateway_role_team_assignments.yml`, because those resources only exist after you create them via your CaC config.
2. **Manual**: Add users to sub-teams via the AAP UI or API.

## Applying Configuration

### Via AAP Job Template (production -- recommended)

The `<team> - Apply Team Config` job template is pre-configured during onboarding with:
- **`env`** set automatically (matches the cluster's environment)
- **API credentials** injected via the gateway credential (`extra_vars` + env vars)
- **Vault credential** auto-provisioned with a placeholder password (update in AAP UI when using vault)
- **Inventory** using the `<team>-cac-localhost` inventory

To apply your configuration:
1. Merge changes to `main`
2. In AAP, sync the `<team>-cac` project (or wait for webhook-triggered sync)
3. Launch the `<team> - Apply Team Config` job template -- no inputs needed, just click "Launch"

### Via CLI (local testing)

Collections are served from the private Automation Hub (not public galaxy.ansible.com). The `ansible.cfg` in this repo lists three Hub Galaxy servers (`rh-certified`, `validated`, `published`). Authenticate via env vars before installing:

```bash
export ANSIBLE_GALAXY_SERVER_HUB_RH_CERTIFIED_USERNAME="admin"
export ANSIBLE_GALAXY_SERVER_HUB_RH_CERTIFIED_PASSWORD="xxx"
export ANSIBLE_GALAXY_SERVER_HUB_VALIDATED_USERNAME="admin"
export ANSIBLE_GALAXY_SERVER_HUB_VALIDATED_PASSWORD="xxx"
export ANSIBLE_GALAXY_SERVER_HUB_PUBLISHED_USERNAME="admin"
export ANSIBLE_GALAXY_SERVER_HUB_PUBLISHED_PASSWORD="xxx"
ansible-galaxy collection install -r collections/requirements.yml
ansible-playbook -i inventory/inventory_dev.yml -l dev playbooks/apply_team_config.yml --vault-password-file=...
```

> **Note**: The `ansible.cfg` Hub URLs default to the dev environment gateway. For staging/prod CLI runs, override via the corresponding `ANSIBLE_GALAXY_SERVER_HUB_<REPO>_URL` env vars. The per-env inventory files (`inventory/*.yml`) are for CLI testing only. The AAP JT uses its own inventory and injects credentials via `extra_vars` (highest Ansible precedence, overrides inventory values).

## Setting Up Vault for Secrets

A vault credential (`<team>-vault-password`) is **auto-provisioned** during onboarding and already attached to the `<team> - Apply Team Config` JT. It is created with a random placeholder password. Before using vault-encrypted secrets, you must set your own password.

> If your team does NOT use vault-encrypted secrets (e.g., you store all sensitive values as AAP Credential objects), skip this section entirely. The placeholder credential is harmless -- it has no effect when `secrets.yml` contains no vault-encrypted content.

**Step-by-step:**

1. **Choose a vault password** for your team. Store it securely outside of Git (e.g., a password manager shared among team admins).

2. **Update the vault credential** in AAP:
   - Navigate to **Credentials** -> `<team>-vault-password`
   - Click **Edit**
   - Set **Vault Password** to your team's chosen password
   - Save

3. **Encrypt sensitive values** in your repo:
   ```bash
   ansible-vault encrypt_string 'my-secret-value' --name 'some_password' --vault-password-file /path/to/vault-pass
   ```

4. **Paste the encrypted string** into `config/<env>/secrets.yml`:
   ```yaml
   some_password: !vault |
             $ANSIBLE_VAULT;1.1;AES256
             ...your encrypted string...
   ```

5. Done. The JT will decrypt vault-encrypted strings automatically at runtime with no prompts.

## Getting Started

1. Define your resources in `config/all/*.yml` (inventories, credentials, projects, job templates)
2. (Optional) Define sub-teams in `config/all/aap_teams.yml`
3. (Optional) Assign roles to sub-teams in `config/all/gateway_role_team_assignments.yml`
4. If using vault-encrypted secrets, follow the [Setting Up Vault for Secrets](#setting-up-vault-for-secrets) section above
5. Commit, push, and apply via the `<team> - Apply Team Config` JT in AAP
6. (Optional, for CLI testing) Update `inventory/inventory_*.yml` with your AAP gateway endpoints

## Important Notes

- Your org name is set by the platform team during onboarding
- You cannot modify resources outside your organization
- **Collections** are served from the private Automation Hub. Your org has Hub Galaxy credentials (`hub-galaxy-rh-certified`, `hub-galaxy-validated`, `hub-galaxy-published`) attached (configured during onboarding) so AAP project sync resolves collections from Hub automatically. For CLI testing, set the Hub username/password env vars (see [Via CLI](#via-cli-local-testing) above).
- Execution Environments are managed by the platform team:
  - **Global EEs** (e.g., `ee-supported`) are available to all orgs
  - **Team-exclusive EEs** can be requested via PR to the `aap-ee-builds` repo
- Custom credential types are managed by the platform team
- Sub-team creation and role assignments are self-service (no platform team needed)
- LDAP mapping for sub-teams requires platform team assistance
