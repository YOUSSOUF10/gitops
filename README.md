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




Apigee Organization Provisioning – Initial Setup Direction

Hello Team,

As preparation for the Apigee Hybrid onboarding, we would like to share the current setup direction before moving forward with the implementation phase.

Current proposal:

* Project ID: `apigee-plg-dev`
* Apigee organization name: `apigee-plg-dev`
* Runtime type: `HYBRID`
* Billing type: `SUBSCRIPTION`

For the API consumer analytics and data residency location, we are considering:

* `europe-central2` (Warsaw)

The objective is to keep analytics and API consumer-related data hosted as close as possible to the Poland region while aligning with European residency requirements.

For the Apigee endpoint, we are considering:

* `https://eu-apigee.googleapis.com/v1/`

The objective is to leverage the European multi-region endpoint strategy for better regional alignment, resiliency, and API management access within the EU scope.

For the first phase, we propose starting with a single Apigee organization.
Once the initial onboarding and governance model are validated, we can later evaluate onboarding an additional organization if required.

Before starting the WebSSO onboarding, we will also need:

* authorized email domain(s)
* initial user list
* expected roles/access levels

  * Viewer
  * Developer
  * Admin
* confirmation of the corporate IdP used for SSO

After the organization provisioning is completed, we will come back to you with all the requirements needed for the runtime plane deployment.

Please note that organization provisioning is not reversible once completed.
For this reason, we kindly ask to ensure that all prerequisites, validations, naming conventions, and residency requirements are fully confirmed before starting the provisioning process.

Best regards,
Youssouf

