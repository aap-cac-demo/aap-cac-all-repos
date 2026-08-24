# aap-ee-builds

Execution Environment (EE) build definitions for the AAP platform. This repo contains `ansible-builder` definitions for all EE images used across the AAP clusters (dev, staging, prod).

EE images are built by the CI pipeline and pushed to the container registry. They are then registered in Controller via the `aap-platform-config` repo.

## EE Classification

EE visibility in Controller is determined by the `organization` field on the EE resource:

| Classification | `organization` field | Visibility | Directory |
|---|---|---|---|
| Global | Omitted (null) | All organizations | `global/<ee-name>/` |
| Team-exclusive | Set to a specific org | Only that organization | `teams/<team-name>/<ee-name>/` |

The directory path encodes the classification -- the CI pipeline and platform CaC derive scope from this convention.

## Directory Structure

```
aap-ee-builds/
├── global/                            # EEs available to all organizations
│   ├── ee-supported/
│   │   └── execution-environment.yml
│   ├── ee-minimal/
│   │   └── execution-environment.yml
│   └── ee-custom-base/
│       ├── execution-environment.yml
│       ├── requirements.yml
│       ├── requirements.txt
│       └── bindep.txt
└── teams/                             # EEs exclusive to specific teams
    └── <team-name>/
        └── <ee-name>/
            ├── execution-environment.yml
            ├── requirements.yml
            ├── requirements.txt
            └── bindep.txt
```

Each EE gets its own directory containing at minimum an `execution-environment.yml` (ansible-builder v3 format). Additional dependency files are included as needed:

- `requirements.yml` -- Ansible collection dependencies
- `requirements.txt` -- Python package dependencies
- `bindep.txt` -- System package dependencies

## Requesting a New EE

1. Create a branch and add your EE definition under the appropriate directory:
   - `teams/<your-team>/` for a team-exclusive EE
   - `global/` for a global EE (requires platform team approval)
2. Include the `execution-environment.yml` and any dependency files
3. Submit a PR to this repo
4. CI will validate the build automatically
5. Platform team reviews and merges
6. CI builds and pushes the image to the registry
7. Platform team updates `aap-platform-config` to register the EE in Controller

## CI/CD Pipeline

The Jenkinsfile implements the following stages:

### On every PR

1. **Detect Changed EEs** -- Uses `git diff` to identify which EE directories were modified
2. **Lint** -- Validates `execution-environment.yml` syntax with `yamllint`
3. **Build** -- Runs `ansible-builder build` to verify the image builds successfully (tagged with PR number)

### On merge to `main`

4. **Build** -- Builds the final image tagged with `latest` and a version number
5. **Push** -- Pushes the image to the container registry

### After push (manual step)

6. A PR is submitted to `aap-platform-config` updating `controller_execution_environments.yml` to register the new/updated EE in Controller

## CaC Registration

After an EE image is built and pushed, it must be registered in Controller via the platform config repo:

```yaml
# aap-platform-config/config/all/controller_execution_environments.yml

# Global EE (organization omitted):
- name: ee-custom-base
  image: "hub.example.com/ee-custom-base:2.0.0"
  pull: missing
  state: present

# Team-exclusive EE (organization set):
- name: ee-team-alpha-ml
  image: "hub.example.com/ee-team-alpha-ml:1.2.0"
  organization: Team-Alpha
  pull: missing
  state: present
```

## Prerequisites

- `ansible-builder` installed on the CI agent
- `podman` (or `docker`) available as the container runtime
- Registry credentials configured in Jenkins (`ee-registry-credentials`)
- Access to `registry.redhat.io` for pulling base images
