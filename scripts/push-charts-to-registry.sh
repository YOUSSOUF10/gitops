#!/usr/bin/env bash
# ============================================================================
# scripts/push-charts-to-registry.sh
# ============================================================================
# Extraire les charts Helm du tarball officiel Apigee Hybrid et les
# pousser vers le registry OCI interne.
#
# Usage :
#   ./scripts/push-charts-to-registry.sh \
#     --tarball /path/to/apigee-hybrid-setup-1.16.0.tar.gz \
#     --registry oci://icr.io/<appUID>/helm-charts
#
# Pré-requis :
#   - helm >= 3.12 (support OCI natif)
#   - Authentifié sur le registry OCI :
#     helm registry login icr.io --username iamapikey --password <IBM_API_KEY>
# ============================================================================

set -euo pipefail

APIGEE_VERSION="1.16.0"

# Charts à pousser (tous ceux nécessaires au déploiement)
CHARTS=(
  apigee-operator        # CRDs + controller
  apigee-org             # ApigeeOrganization
  apigee-datastore       # Cassandra
  apigee-telemetry       # logs/metrics GCP
  apigee-ingress-manager # ApigeeIngressGateway (appelé "apigee-ingress" dans certains tarballs)
  apigee-env             # ApigeeEnvironment
  apigee-virtualhost     # ApigeeEnvGroup + virtualhosts
  apigee-redis           # Redis (cache sessions, optionnel mais inclus)
)

# ---------------------------------------------------------------------------
# Parsing arguments
# ---------------------------------------------------------------------------
TARBALL=""
REGISTRY=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --tarball)   TARBALL="$2";   shift 2 ;;
    --registry)  REGISTRY="$2";  shift 2 ;;
    *) echo "Usage: $0 --tarball <path> --registry <oci://...>"; exit 1 ;;
  esac
done

[ -z "$TARBALL" ]  && { echo "❌ --tarball requis"; exit 1; }
[ -z "$REGISTRY" ] && { echo "❌ --registry requis"; exit 1; }
[ -f "$TARBALL" ]  || { echo "❌ Fichier introuvable : $TARBALL"; exit 1; }

# ---------------------------------------------------------------------------
# Extraction
# ---------------------------------------------------------------------------
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo "📦 Extraction du tarball..."
tar xzf "$TARBALL" -C "$TMPDIR"

# Trouver le répertoire racine (peut varier selon la version)
SETUP_DIR=$(find "$TMPDIR" -maxdepth 1 -type d -name "apigee-hybrid-setup*" | head -1)
[ -d "$SETUP_DIR" ] || { echo "❌ Répertoire apigee-hybrid-setup introuvable dans le tarball"; exit 1; }

CHARTS_DIR="$SETUP_DIR/charts"
[ -d "$CHARTS_DIR" ] || CHARTS_DIR="$SETUP_DIR/helm-charts"
[ -d "$CHARTS_DIR" ] || { echo "❌ Dossier charts/ introuvable dans $SETUP_DIR"; exit 1; }

echo "📂 Charts trouvés dans : $CHARTS_DIR"
ls -1 "$CHARTS_DIR"

# ---------------------------------------------------------------------------
# Package + push
# ---------------------------------------------------------------------------
PUSHED=0
FAILED=0

for chart in "${CHARTS[@]}"; do
  chart_dir="$CHARTS_DIR/$chart"
  if [ ! -d "$chart_dir" ]; then
    echo "⚠️  Chart $chart introuvable dans le tarball — skip"
    FAILED=$((FAILED + 1))
    continue
  fi

  echo ""
  echo "=== $chart ==="

  # Vérifier la version dans Chart.yaml
  chart_version=$(grep '^version:' "$chart_dir/Chart.yaml" | awk '{print $2}')
  echo "   Version chart : $chart_version"

  # Package
  helm package "$chart_dir" --destination "$TMPDIR/packages/" --quiet

  # Push vers OCI
  pkg=$(ls "$TMPDIR/packages/${chart}-"*.tgz 2>/dev/null | head -1)
  if [ -z "$pkg" ]; then
    echo "   ❌ Package introuvable après helm package"
    FAILED=$((FAILED + 1))
    continue
  fi

  echo "   ⬆️  Push vers $REGISTRY/$chart:$chart_version"
  helm push "$pkg" "$REGISTRY"

  echo "   ✅ OK"
  PUSHED=$((PUSHED + 1))
done

echo ""
echo "============================================="
echo "   Poussés : $PUSHED / ${#CHARTS[@]}"
echo "   Échoués : $FAILED"
echo "============================================="
echo ""
echo "Vérification — lister les charts dans le registry :"
echo "   helm search repo --regexp '.*apigee.*' (si configuré comme repo)"
echo "   ou : skopeo list-tags docker://icr.io/<appUID>/helm-charts/apigee-operator"
