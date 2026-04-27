# Apigee Hybrid 1.16 — Dépôt GitOps (v2 — charts éditeur Google)

Dépôt de déploiement CD pour Apigee Hybrid sur ROKS, piloté par ArgoCD.
Consomme les charts Helm **officiels Google** (sans fork) depuis un registry OCI interne.

## Principe

Les charts Google ne sont jamais forkés ni modifiés. Ils sont poussés tels quels dans
le registry OCI interne et surchargés via les fichiers `values/` de ce repo.

Un seul chart local (`apigee-extras`) gère ce que Google ne couvre pas :
ExternalSecrets, Ingress Traefik, ServersTransport, NetworkPolicies, PDB.

## Par tenant : 3 fichiers values

| Fichier | Chart cible | Contenu |
|---------|-------------|---------|
| `values-<tenant>.yaml` | Google `apigee-env` | replicas, resources, SA refs |
| `values-<tenant>-virtualhost.yaml` | Google `apigee-virtualhost` | hosts, envgroup, routingRules |
| `values-<tenant>-extras.yaml` | Local `apigee-extras` | Vault paths, Traefik, NetPol |

## Sync-waves

| Wave | Chart | Type |
|------|-------|------|
| 0 | namespace | local |
| 5 | apigee-operator | Google OCI |
| 10 | apigee-org + apigee-telemetry | Google OCI |
| 15 | apigee-datastore (Cassandra) | Google OCI |
| 25 | apigee-extras (ExternalSecrets) | local |
| 28 | apigee-ingress-manager | Google OCI |
| 30 | apigee-env + apigee-virtualhost | Google OCI |
| 35 | apigee-extras (Traefik exposure) | local |

## Workflow upgrade Apigee (ex: 1.16 → 1.17)

1. Télécharger le tarball officiel
2. `./scripts/push-charts-to-registry.sh --tarball ... --registry ...`
3. Bumper `targetRevision` dans les AppSets
4. Vérifier les release notes Google, adapter les values si besoin
5. MR + merge → ArgoCD upgrade dans l'ordre des sync-waves

## Démarrage

Voir `docs/argocd-bootstrap.md`
