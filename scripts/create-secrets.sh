#!/usr/bin/env bash
set -euo pipefail

# Generates and applies the Kubernetes Secret required by lab-gitea at install time.
# Secrets are never written to disk or committed to git.

NAMESPACE="gitea"
SECRET_NAME="gitea-secrets"
DRY_RUN="false"
WITHOUT_OIDC="false"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Creates or updates the Kubernetes Secret required by the lab-gitea Helm chart.
Cryptographic keys (db-password, secret-key, internal-token, jwt-secret) are
generated locally with openssl unless provided via environment variables.

Options:
  -n, --namespace NAME      Target Kubernetes namespace (default: gitea)
  -s, --secret-name NAME    Kubernetes Secret name (default: gitea-secrets)
      --without-oidc        Skip OIDC client ID / secret prompts
      --dry-run             Print the kubectl command target without applying
  -h, --help                Show this help message

Optional Environment Variables:
  DB_PASSWORD               PostgreSQL password (auto-generated if unset)
  GITEA_SECRET_KEY          Gitea SECRET_KEY (auto-generated if unset)
  GITEA_INTERNAL_TOKEN      Gitea INTERNAL_TOKEN (auto-generated if unset)
  GITEA_JWT_SECRET          Gitea OAuth2 JWT_SECRET (auto-generated if unset)
  OIDC_CLIENT_ID            Zitadel OIDC client ID (prompted if unset)
  OIDC_CLIENT_SECRET        Zitadel OIDC client secret (prompted silently if unset)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    -s|--secret-name)
      SECRET_NAME="$2"
      shift 2
      ;;
    --without-oidc)
      WITHOUT_OIDC="true"
      shift
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: Unknown option '$1'" >&2
      usage >&2
      exit 1
      ;;
  esac
done

for cmd in kubectl openssl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command '$cmd' not found in PATH." >&2
    exit 1
  fi
done

# Generate cryptographically strong secrets if not supplied
DB_PASSWORD="${DB_PASSWORD:-$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)}"
GITEA_SECRET_KEY="${GITEA_SECRET_KEY:-$(openssl rand -hex 32)}"
GITEA_INTERNAL_TOKEN="${GITEA_INTERNAL_TOKEN:-$(openssl rand -base64 64 | tr -d '\n')}"
GITEA_JWT_SECRET="${GITEA_JWT_SECRET:-$(openssl rand -base64 32 | tr '+/' '-_' | tr -d '=')}"

DB_KEY="db-password"

ARGS=(
  --namespace "$NAMESPACE"
  --from-literal="${DB_KEY}=${DB_PASSWORD}"
  --from-literal="secret-key=${GITEA_SECRET_KEY}"
  --from-literal="internal-token=${GITEA_INTERNAL_TOKEN}"
  --from-literal="jwt-secret=${GITEA_JWT_SECRET}"
)

if [[ "$WITHOUT_OIDC" == "false" ]]; then
  if [[ -z "${OIDC_CLIENT_ID:-}" ]]; then
    read -r -p "Zitadel OIDC Client ID: " OIDC_CLIENT_ID
  fi
  if [[ -z "${OIDC_CLIENT_SECRET:-}" ]]; then
    read -r -s -p "Zitadel OIDC Client Secret: " OIDC_CLIENT_SECRET
    echo ""
  fi
  if [[ -z "${OIDC_CLIENT_ID}" || -z "${OIDC_CLIENT_SECRET}" ]]; then
    echo "Error: OIDC_CLIENT_ID and OIDC_CLIENT_SECRET must not be empty (or pass --without-oidc)." >&2
    exit 1
  fi
  ARGS+=(
    --from-literal="oidc-client-id=${OIDC_CLIENT_ID}"
    --from-literal="oidc-client-secret=${OIDC_CLIENT_SECRET}"
  )
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo "[dry-run] Would create/update Secret '${SECRET_NAME}' in namespace '${NAMESPACE}'."
  exit 0
fi

kubectl create secret generic "$SECRET_NAME" \
  "${ARGS[@]}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secret '${SECRET_NAME}' applied in namespace '${NAMESPACE}'."
