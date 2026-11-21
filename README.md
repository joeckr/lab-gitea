# lab-gitea

Source-of-truth Helm chart and deployment configuration for running **Gitea** in a hardened Kubernetes homelab on **Talos Linux**.

## Architecture

- **Gitea**: Official rootless container image (`docker.gitea.com/gitea:1.23.7-rootless`, UID/GID `1000:1000`) listening on unprivileged HTTP port `3000`.
- **PostgreSQL**: Hardened rootless PostgreSQL from [`joeckr/oci-postgres`](https://github.com/joeckr/oci-postgres) (`ghcr.io/joeckr/postgres:18`, `PGDATA=/tmp/data`).
- **Storage**: Longhorn `ReadWriteOnce` PersistentVolumeClaims (`storageClassName: longhorn`) with `Recreate` deployment strategies to avoid RWO Multi-Attach deadlocks during rollouts.
- **Security**: Fully compliant with Kubernetes **Pod Security Standards (`restricted`)** — `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`, `seccompProfile: RuntimeDefault`, `automountServiceAccountToken: false`, and Talos control-plane/master tolerations.
- **Routing**: Kubernetes Gateway API `HTTPRoute` (`gateway.networking.k8s.io/v1`) attached to a Traefik `Gateway` (`traefik-gateway` in namespace `gateway`) behind a Cloudflare Tunnel, serving `https://gitea.joeckr.dev/`.
- **Authentication (OIDC)**: Zitadel OpenID Connect (`https://zitadel.joeckr.dev/.well-known/openid-configuration`) auto-configured idempotently on startup via an init container (`environment-to-ini` -> `gitea migrate` -> `gitea admin auth add-oauth` / `update-oauth`).
- **Zero Secrets in Git**: All sensitive values (`db-password`, `secret-key`, `internal-token`, `jwt-secret`, `oidc-client-id`, `oidc-client-secret`) are referenced from an install-time Kubernetes `Secret` (`gitea-secrets`) via `secretKeyRef`.

---

## Directory Structure

```text
.
├── .github/
│   └── workflows/
│       ├── lint.yml                 # Lints workflows, commits, and shell scripts
│       ├── security.yml             # Secret scanning (betterleaks) and zizmor audits
│       ├── release.yml              # Semantic release and Helm chart publishing to GHCR
│       └── test_release.yml         # PR dry-run test for releases and chart packaging
├── chart/
│   ├── Chart.yaml                   # Helm chart metadata
│   ├── values.yaml                  # Non-secret configuration defaults
│   ├── .helmignore
│   └── templates/
│       ├── _helpers.tpl             # Shared labels and Gitea env helpers
│       ├── pvc.yaml                 # Longhorn PVCs for Gitea and PostgreSQL
│       ├── postgres-deployment.yaml # joeckr/oci-postgres Deployment
│       ├── postgres-service.yaml    # Internal ClusterIP Service for PostgreSQL
│       ├── gitea-configmap.yaml     # Idempotent migrate + Zitadel OIDC init script
│       ├── deployment.yaml          # Gitea Deployment + init containers
│       ├── service.yaml             # Gitea HTTP (and optional SSH) Service
│       ├── httproute.yaml           # Gateway API HTTPRoute for Traefik
│       ├── ingress.yaml             # Optional Ingress fallback (disabled by default)
│       └── NOTES.txt                # Post-install verification commands
├── scripts/
│   └── create-secrets.sh            # Install-time Secret generator/applier
├── compose.yml                      # Local Gitea + PostgreSQL test stack
├── hk.pkl                           # Git hooks and lint checks
├── mise.toml                        # Tool versions and task runner
└── README.md
```

---

## Deploying to Talos Linux Kubernetes Homelab

### 1. Create a `restricted` PSS Namespace

```sh
kubectl create namespace gitea
kubectl label namespace gitea \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted
```

### 2. Configure Zitadel OIDC Client

In Zitadel (`https://zitadel.joeckr.dev`), create a new **Web** application (OIDC) for Gitea with:
- **Authentication Method**: `Basic` or `Post` (confidential client with Client ID and Client Secret)
- **Redirect URI**: `https://gitea.joeckr.dev/user/oauth2/Zitadel/callback`
  *(If you change `oidc.name` in `values.yaml`, replace `Zitadel` in the callback path with that name.)*
- **Grant Types**: `Authorization Code`
- **Scopes**: `openid`, `email`, `profile` (plus `groups` if using group mapping)

### 3. Configure Cloudflare Tunnel

Ensure your Cloudflare Tunnel (`lab-cloudflare-tunnel`) routes `gitea.joeckr.dev` to your Traefik Kubernetes Gateway service (`http://traefik.gateway.svc.cluster.local:80` or the LoadBalancer endpoint).

### 4. Create the Install-Time Kubernetes Secret

Run the helper script to generate random cryptographic keys locally and apply `gitea-secrets` directly to the cluster (nothing is written to disk):

```sh
./scripts/create-secrets.sh --namespace gitea
# or: mise run secrets
```

If you want to deploy without OIDC first, pass `--without-oidc`.

### 5. Install or Upgrade the Helm Chart

```sh
helm upgrade --install gitea ./chart \
  --namespace gitea
```

Optional overrides for OIDC group-based admin mapping or Traefik Gateway reference:

```sh
helm upgrade --install gitea ./chart \
  --namespace gitea \
  --set oidc.scopes="openid email profile groups" \
  --set oidc.groupClaimName="groups" \
  --set oidc.adminGroup="gitea-admins" \
  --set gateway.parentRefs[0].name="traefik-gateway" \
  --set gateway.parentRefs[0].namespace="gateway" \
  --set gateway.parentRefs[0].sectionName="web"
```

### 6. Verify Deployment & PSS Compliance

```sh
# Confirm Longhorn PVCs are Bound and pods are Running (no PSA rejections)
kubectl -n gitea get pvc,pods

# Check init container logs (DB wait, migrations, Zitadel OIDC reconciliation)
kubectl -n gitea logs deploy/gitea -c configure-gitea

# Check Gateway API HTTPRoute acceptance
kubectl -n gitea get httproute gitea-httproute -o yaml

# Confirm Zitadel OIDC auth source is registered in Gitea
kubectl -n gitea exec deploy/gitea -- \
  gitea --config /etc/gitea/app.ini admin auth list
```

---

## PSS `restricted` Compliance Matrix

| Security Dimension | `restricted` PSS Requirement | Implementation |
| --- | --- | --- |
| **Workload Execution** | `runAsNonRoot: true` | Gitea (`1000:1000` rootless), `joeckr/oci-postgres` (arbitrary non-root UID, GID 0) |
| **Capabilities** | `capabilities.drop: ["ALL"]` | Applied to all init and application containers |
| **Privilege Escalation** | `allowPrivilegeEscalation: false` | Applied to all init and application containers |
| **Seccomp Profile** | `RuntimeDefault` | Set in `podSecurityContext` on both Deployments |
| **Service Account Token** | Disabled unless needed | `automountServiceAccountToken: false` on both Deployments |
| **Storage Permissions** | Non-root writable PVCs | `fsGroup` + `fsGroupChangePolicy: OnRootMismatch` on Longhorn PVCs |
| **Ports** | Unprivileged (> 1024) | Gitea HTTP `3000`, SSH `2222`, PostgreSQL `5432` |

---

## Key Configuration Values (`chart/values.yaml`)

| Parameter | Description | Default |
| --- | --- | --- |
| `existingSecret` | Name of the install-time Kubernetes Secret | `gitea-secrets` |
| `gitea.image` / `tag` | Gitea rootless container image | `docker.gitea.com/gitea:1.23.7-rootless` |
| `gitea.domain` | Public domain name | `gitea.joeckr.dev` |
| `gitea.rootUrl` | External base URL | `https://gitea.joeckr.dev/` |
| `gitea.storage.storageClass` | PVC StorageClass for Gitea data & config | `longhorn` |
| `gitea.storage.size` | PVC size for Gitea | `30Gi` |
| `gitea.ssh.enabled` | Enable built-in Go SSH server & SSH Service | `false` |
| `oidc.enabled` | Auto-reconcile OIDC auth source on startup | `true` |
| `oidc.name` | Display name of the OIDC login button | `Zitadel` |
| `oidc.autoDiscoverUrl` | OIDC `.well-known/openid-configuration` URL | `https://zitadel.joeckr.dev/.well-known/openid-configuration` |
| `oidc.scopes` | Space-separated OIDC scopes | `openid email profile` |
| `oidc.groupClaimName` | Optional OIDC claim for group mapping | `""` |
| `oidc.adminGroup` | Optional OIDC group granted Gitea admin | `""` |
| `postgres.enabled` | Deploy `joeckr/oci-postgres` alongside Gitea | `true` |
| `postgres.image` / `tag` | Hardened rootless PostgreSQL image | `ghcr.io/joeckr/postgres:18` |
| `postgres.storage.storageClass` | PVC StorageClass for PostgreSQL | `longhorn` |
| `postgres.storage.size` | PVC size for PostgreSQL | `30Gi` |
| `gateway.enabled` | Create Gateway API `HTTPRoute` | `true` |
| `gateway.parentRefs` | Target Traefik `Gateway` reference(s) | `gateway/traefik-gateway` (`web`) |
| `gateway.hostnames` | Hostnames matched by the `HTTPRoute` | `["gitea.joeckr.dev"]` |
| `ingress.enabled` | Fallback `networking.k8s.io/v1` Ingress | `false` |

---

## Local Testing & Development

```sh
# Install tools and git hooks
mise run install

# Run all linters and secret/security checks
mise run check

# Lint and render Helm manifests locally
mise run helm-l
mise run helm-t

# Run Gitea + joeckr/oci-postgres locally via Podman Compose (http://localhost:3000)
mise run compose
mise run logs
mise run down
```

---

## Conventional Commits & Releases

Commits follow [Conventional Commits](https://www.conventionalcommits.org/). Merging to `main` automatically computes the next semantic version, updates `chart/Chart.yaml`, creates a GitHub Release, and publishes the Helm chart to GHCR.

## License

Please refer to the `LICENSE` file for details.
