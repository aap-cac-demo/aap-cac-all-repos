# aap-hub-collections

Custom Ansible collections published to the private Automation Hub for internal consumption. All collections share a single configurable namespace (default: `hig`).

This repo is owned by the platform team but open to PRs from any tenant team. The platform team reviews, merges, and CI handles the build and publish.

## How It Works

```
Team PR  ->  Platform review  ->  Merge  ->  CI builds + publishes  ->  Hub staging  ->  Approve  ->  Hub published
```

Collections land in Hub's `staging` repository after publish. With auto-approve enabled, they are automatically promoted to `published`. Without auto-approve, a Hub admin must approve them from the approval dashboard.

All tenant organizations already have the `hub-galaxy-published` credential, so published collections are immediately available for consumption.

## Namespace

All collections use the namespace defined in [`_config.yml`](_config.yml). This value **must** match `hub_custom_collection_namespace` in `aap-platform-config/config/{env}/_commons.yml`.

CI validates that every collection's `galaxy.yml` uses the correct namespace. PRs with a mismatched namespace fail the pipeline.

## Directory Structure

```
aap-hub-collections/
├── README.md
├── Jenkinsfile
├── _config.yml                           # Namespace defined once here
├── ansible.cfg                           # Hub auth for build + publish
├── playbooks/
│   ├── publish_collection.yml            # Manual build + publish fallback
│   └── _publish_one.yml                  # Helper: build + publish one collection
├── _collection_template/                 # Copy this to start a new collection
│   ├── galaxy.yml                        # Namespace pre-filled
│   ├── roles/
│   ├── plugins/
│   │   └── modules/
│   └── README.md
└── collections/
    └── <collection_name>/                # One directory per collection
        ├── galaxy.yml
        ├── roles/
        ├── plugins/
        └── README.md
```

## Contributing a New Collection

1. Copy the template:
   ```bash
   cp -r _collection_template/ collections/<your_collection_name>/
   ```

2. Edit `collections/<your_collection_name>/galaxy.yml`:
   - Set `name` to your collection name (must match the directory name)
   - Set `version` to `0.1.0` (or appropriate initial version)
   - Fill in `description` and `authors`
   - **Do not change `namespace`** -- it is pre-filled from the org standard

3. Write your roles, plugins, and modules under the standard Ansible collection layout.

4. Open a PR to this repo. CI will:
   - Validate that the namespace matches `_config.yml`
   - Lint with `yamllint`
   - Test-build the tarball with `ansible-galaxy collection build`

5. Platform team reviews and merges.

6. On merge to `main`, CI builds and publishes the tarball to Hub.

7. Consumers add the collection to their `collections/requirements.yml`:
   ```yaml
   collections:
     - name: hig.<your_collection_name>
       version: ">=0.1.0"
   ```

## Updating an Existing Collection

1. PR your changes to the collection directory.
2. **Bump `version`** in `galaxy.yml` (Hub rejects duplicate versions).
3. Platform reviews and merges. CI publishes the new version.

## CI Pipeline (Jenkinsfile)

| Stage | On PR | On merge to main |
|-------|-------|------------------|
| Detect changed collections | Yes | Yes |
| Validate namespace | Yes | Yes |
| Lint | Yes | Yes |
| Build tarball | Yes | Yes |
| Publish to Hub | No | Yes |

The `COLLECTION_FILTER` parameter lets you target a specific collection (e.g., `common_network`). Leave blank to auto-detect from the diff.

## Manual Publish (CLI Fallback)

When CI didn't run or for ad-hoc re-publishing:

```bash
# Set Hub credentials (platform admin or any user with upload + approve permissions)
export ANSIBLE_GALAXY_SERVER_HUB_PUBLISHED_USERNAME="admin"
export ANSIBLE_GALAXY_SERVER_HUB_PUBLISHED_PASSWORD="xxx"

# Publish a specific collection
ansible-playbook playbooks/publish_collection.yml \
  -e collection_name=common_network

# Publish all collections
ansible-playbook playbooks/publish_collection.yml
```

## Hub Credentials

CI reuses the same Jenkins `usernamePassword` credential (`aap-hub-credentials`) as the `aap-platform-config` pipeline. This is the platform admin account, which has full Hub permissions including upload and approval.

The same credentials provide read access to Hub repositories for resolving collection dependencies during build. The `ansible.cfg` in this repo points to the Hub Galaxy servers (`rh-certified`, `validated`, `published`).

**Why not a dedicated service account?** A dedicated least-privilege user (`svc-hub-publisher`) with `galaxy.collection_namespace_owner` + `galaxy.collection_curator` roles was considered but adds complexity (user creation, team provisioning, password rotation) with limited benefit -- this pipeline is already platform-team controlled, and the Jenkins credential must be configured manually regardless. If least-privilege becomes a requirement, see the upgrade options documented in `aap-platform-config/config/all/hub_group_roles.yml`.

## Prerequisites

- The `hub_custom_collection_namespace` namespace must exist in Hub (created by `aap-platform-config` dispatch from `hub_namespace.yml`)
- Jenkins credential `aap-hub-credentials` must be configured (same credential used by `aap-platform-config`)
- Hub `staging` and `published` repositories must exist (ensured by `aap-platform-config` `hub_collection_repository.yml`)

## Related Repos

| Repository | Purpose |
|---|---|
| `aap-platform-config` | Platform-level CaC (namespace, Hub repo config) |
| `aap-ee-builds` | Execution Environment build definitions |
| `aap-team-template` | Template for per-team CaC repos |
