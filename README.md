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












# Terraform — Provisionnement Organisation(s) Apigee Hybrid

> **Scope de ce repo** : provisionnement GCP de la couche organisation Apigee (activation des APIs, création de l'organisation).
> La gestion des **Environment Groups** et des **Environments** est intentionnellement gérée dans un repo Terraform séparé, car leur cycle de vie est indépendant de celui de l'organisation.

---

## Table des matières

1. [Contexte & architecture multi-hybridation](#1-contexte--architecture-multi-hybridation)
2. [Cycle de vie — Pourquoi des repos séparés](#2-cycle-de-vie--pourquoi-des-repos-séparés)
3. [Structure du repo](#3-structure-du-repo)
4. [Paramètres clés](#4-paramètres-clés)
5. [Pré-requis](#5-pré-requis)
6. [Utilisation](#6-utilisation) *(⚠️ phase transitoire — backend local jusqu'à ouverture des flux GitLab → GCP)*
7. [Multi-hybridation — Gérer plusieurs organisations](#7-multi-hybridation--gérer-plusieurs-organisations)
8. [Services GCP activés](#8-services-gcp-activés)
9. [Contraintes & points d'attention](#9-contraintes--points-dattention)
10. [Références](#10-références)

---

## 1. Contexte & architecture multi-hybridation

Ce repo gère le provisionnement Terraform d'une ou plusieurs **organisations Apigee Hybrid** sur GCP. En mode **HYBRID**, le plan de contrôle (Management Plane) réside sur GCP, tandis que le plan d'exécution (Runtime Plane) est déployé on-premises ou sur un cluster OpenShift (ROKS, OCP, etc.).

```
┌──────────────────────────────────────────────────────────────────┐
│  GCP Project A  (covea-apigee-hprod)                             │
│  ┌──────────────────────────────────────┐                        │
│  │  Apigee Organization  [HYBRID]       │  ← ce repo             │
│  │  - billing_type: SUBSCRIPTION        │                        │
│  │  - api_consumer_data_location: eu-w9 │                        │
│  └──────────────────────────────────────┘                        │
│                                                                  │
│  Environment Groups & Environments  ← repo séparé               │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│  GCP Project B  (covea-apigee-prod)                              │
│  ┌──────────────────────────────────────┐                        │
│  │  Apigee Organization  [HYBRID]       │  ← ce repo             │
│  │  - paramètres différents             │                        │
│  └──────────────────────────────────────┘                        │
└──────────────────────────────────────────────────────────────────┘

         ▼ Runtime Plane (déployé via ArgoCD / Helm)
┌─────────────────────────────────────────────┐
│  OpenShift Cluster A  (ROKS non-prod)        │
│  OpenShift Cluster B  (ROKS prod)            │
└─────────────────────────────────────────────┘
```

Une **hybridation** correspond à un couple `(GCP Project, Apigee Organization)`. Il est possible d'en gérer plusieurs dans ce repo via des fichiers `.tfvars` distincts, un par environnement/organisation cible.

---

## 2. Cycle de vie — Pourquoi des repos séparés

| Ressource | Fréquence de modification | Repo |
|---|---|---|
| `google_apigee_organization` | Rare — création quasi-unique, modifications exceptionnelles | **Ce repo** |
| Services GCP activés | Rare — à la création du projet | **Ce repo** |
| `google_apigee_envgroup` | Modéré — ajout d'hostnames, nouveaux groupes | Repo `apigee-envgroups` |
| `google_apigee_environment` | Modéré — nouveaux environnements, modification de configs | Repo `apigee-envgroups` |
| `google_apigee_envgroup_attachment` | Modéré | Repo `apigee-envgroups` |

**Raisons clés de la séparation :**

- **Blast radius réduit** : un `terraform apply` sur les environments n'a aucun risque de toucher à l'organisation racine, et vice versa.
- **Permissions distinctes** : le pipeline de provisionnement d'organisation nécessite des droits élevés (`roles/apigee.admin`, `roles/serviceusage.serviceUsageAdmin`) qui ne doivent pas être exposés aux pipelines de gestion du cycle de vie des environnements.
- **State isolation** : l'état Terraform de l'organisation est stable et immuable dans le temps ; le séparer évite les conflits de state lors de modifications fréquentes sur les environments.
- **Séquencement** : l'organisation doit exister avant toute création d'environment group ou environment. La dépendance est unidirectionnelle : `org → envgroup → env`.

---

## 3. Structure du repo

```
001-Terraform/
├── environments/
│   ├── hprod.tfvars          # Paramètres organisation hors-production
│   ├── pprod-interne.tfvars  # Paramètres organisation pré-production
│   └── prod-interne.tfvars   # Paramètres organisation production
├── modules/
│   └── apigee/
│       ├── services/         # Activation des APIs GCP
│       └── organization/     # Création de l'organisation Apigee
├── backend.tf                # Configuration du backend Terraform (GCS)
├── global.tfvars             # Variables communes à toutes les organisations
├── main.tf                   # Orchestration des modules
├── managed.tf                # (optionnel) Ressources complémentaires gérées
├── outputs.tf                # Outputs exportés
├── providers.tf              # Provider Google avec endpoint régional
├── terraform.tf              # Bloc terraform { required_providers, ... }
├── variables.tf              # Déclaration des variables
└── version.txt               # Version du module / du déploiement
```

### Séparation `global.tfvars` / `environments/*.tfvars`

| Fichier | Contenu |
|---|---|
| `global.tfvars` | Variables identiques pour toutes les organisations : région par défaut, labels communs, etc. |
| `environments/<env>.tfvars` | Variables propres à une organisation : `project_id`, `display_name`, `api_consumer_data_location`, liste de services, etc. |

Les deux fichiers sont passés conjointement à chaque `terraform` invocation :

```bash
terraform plan \
  -var-file="global.tfvars" \
  -var-file="environments/hprod.tfvars"
```

---

## 4. Paramètres clés

### Variables d'organisation (`variables.tf`)

| Variable | Description | Exemple |
|---|---|---|
| `project_id` | ID du projet GCP cible | `covea-apigee-hprod` |
| `display_name` | Nom affiché de l'organisation dans la console | `apigee-org-hors-prod` |
| `description` | Description libre | `Organisation Apigee HPROD – Terraform` |
| `runtime_type` | Mode de déploiement | `HYBRID` (ne pas utiliser `CLOUD`) |
| `billing_type` | Type de facturation | `SUBSCRIPTION` |
| `retention` | Rétention des données Analytics | `MINIMUM` ou `THIRTY_SIX_MONTHS` |
| `api_consumer_data_location` | Région de résidence des données consommateur | `europe-west9` (Paris) |
| `apigee_custom_endpoint` | Endpoint régional Apigee | `https://eu-apigee.googleapis.com/v1/` |
| `apigee_services` | Liste des APIs GCP à activer | voir section [Services GCP activés](#8-services-gcp-activés) |

### Point d'attention : `api_consumer_data_location`

Pour respecter les exigences de **résidence des données (RGPD / réglementation bancaire française)**, cette valeur doit impérativement être positionnée sur `europe-west9` (Paris). Elle est non modifiable après la création de l'organisation.

### Point d'attention : `runtime_type = "HYBRID"`

En mode `HYBRID` :
- Le Management Plane est géré par Google sur GCP.
- **CMEK n'est pas supporté sur le Management Plane** (contrairement à Apigee X). Le chiffrement du Runtime Plane est géré via des clés AES-256 encodées en Base64 dans `overrides.yaml`, gérées par Vault/ESO.
- Le champ `authorized_network` et les configurations VPC peering ne s'appliquent pas.

---

## 5. Pré-requis

### Outils

| Outil | Version minimale |
|---|---|
| Terraform | >= 1.5.0 |
| Google Provider (`hashicorp/google`) | >= 5.0.0 |
| `gcloud` CLI | >= 450.0.0 |

### Permissions requises (Service Account du pipeline)

| Rôle IAM | Justification |
|---|---|
| `roles/apigee.admin` | Création et gestion de l'organisation Apigee |
| `roles/serviceusage.serviceUsageAdmin` | Activation des APIs GCP |
| `roles/storage.objectAdmin` | Accès au bucket GCS pour le state Terraform |
| `roles/iam.serviceAccountTokenCreator` | Impersonation du SA pour les pipelines CI/CD |

### Backend GCS

Chaque organisation doit disposer de son propre **prefix de state** dans le bucket GCS pour éviter tout conflit. Exemple :

```hcl
# backend.tf
terraform {
  backend "gcs" {
    bucket = "covea-terraform-states"
    prefix = "apigee/org/hprod"   # à adapter par organisation
  }
}
```

> ⚠️ **Voir section [Phase transitoire — Backend & CI/CD](#phase-transitoire--backend--cicd) ci-dessous.**

---

## 6. Utilisation

### ⚠️ Phase transitoire — Backend & CI/CD

> **Statut actuel** : le bucket GCS pour le state Terraform et le pipeline GitLab CI ne sont pas encore disponibles. Le prérequis bloquant est l'**ouverture de flux réseau entre les runners GitLab (on-premises) et GCP** (`*.googleapis.com:443`), en cours de traitement.

**En attendant**, les `terraform` sont exécutés **manuellement en local** depuis un poste disposant d'un accès GCP :

```bash
# Phase transitoire — exécution locale
gcloud auth application-default login

# Backend local (state stocké en local, à ne pas committer)
terraform init

terraform plan \
  -var-file="global.tfvars" \
  -var-file="environments/hprod.tfvars"

terraform apply \
  -var-file="global.tfvars" \
  -var-file="environments/hprod.tfvars"
```

> ⚠️ En mode local, le `backend.tf` doit être commenté ou remplacé par un backend `local` temporaire. **Ne jamais committer le fichier `terraform.tfstate` généré localement.**

```hcl
# backend.tf — version temporaire phase transitoire
terraform {
  backend "local" {
    path = "terraform.tfstate"  # fichier à ajouter dans .gitignore
  }
}
```

**Ce qui changera une fois les prérequis disponibles :**

| Élément | Phase transitoire | Phase cible |
|---|---|---|
| Exécution | Manuelle en local | Pipeline GitLab CI (job `plan` + `apply` manuel) |
| Authentification | `gcloud auth application-default login` | Service Account + Workload Identity ou SA Key dans GitLab Variables |
| Backend state | `local` (fichier `.tfstate` local) | GCS bucket avec prefix par organisation |
| `backend.tf` | Backend `local` commenté | Backend `gcs` avec `bucket` et `prefix` |
| Gestion du state | Manuelle (backup obligatoire) | Gérée par GCS (versioning activé) |

**Migration du state local vers GCS** (à effectuer lors de l'activation du pipeline) :

```bash
# 1. Décommenter le backend GCS dans backend.tf
# 2. Réinitialiser — Terraform proposera de migrer le state existant
terraform init -migrate-state \
  -backend-config="prefix=apigee/org/hprod"

# 3. Vérifier que le state est bien présent dans GCS
gsutil ls gs://covea-terraform-states/apigee/org/hprod/
```

---

### Initialisation (phase cible)

```bash
# Authentification via SA impersonation (CI/CD)
gcloud auth application-default login

# Init avec backend GCS spécifique à l'organisation
terraform init \
  -backend-config="prefix=apigee/org/hprod"
```

### Plan

```bash
terraform plan \
  -var-file="global.tfvars" \
  -var-file="environments/hprod.tfvars" \
  -out=tfplan-hprod
```

### Apply

```bash
terraform apply tfplan-hprod
```

### Destroy

> ⚠️ **La suppression d'une organisation Apigee est irréversible et entraîne la perte de toutes les configurations associées.** Elle ne doit être exécutée qu'après désinstallation complète du Runtime Plane et archivage des configurations Apigee (proxies, products, developers).

```bash
terraform destroy \
  -var-file="global.tfvars" \
  -var-file="environments/hprod.tfvars"
```

---

## 7. Multi-hybridation — Gérer plusieurs organisations

Chaque organisation Apigee correspond à un **projet GCP distinct** et à un fichier `.tfvars` dédié. Le même codebase Terraform est réutilisé ; seule la combinaison `project_id` + `tfvars` change.

### Exemple de matrice d'organisations

| Fichier tfvars | `project_id` | `runtime_type` | `api_consumer_data_location` | Usage |
|---|---|---|---|---|
| `hprod.tfvars` | `covea-apigee-hprod` | `HYBRID` | `europe-west9` | Hors-production (dev, intégration) |
| `pprod-interne.tfvars` | `covea-apigee-pprod` | `HYBRID` | `europe-west9` | Pré-production interne |
| `prod-interne.tfvars` | `covea-apigee-prod` | `HYBRID` | `europe-west9` | Production interne |

### Exécution en pipeline (exemple GitLab CI)

```yaml
# .gitlab-ci.yml — extrait
.terraform_base:
  image: hashicorp/terraform:1.9
  before_script:
    - terraform init -backend-config="prefix=apigee/org/${ORG_ENV}"

plan:hprod:
  extends: .terraform_base
  variables:
    ORG_ENV: hprod
  script:
    - terraform plan -var-file="global.tfvars" -var-file="environments/hprod.tfvars" -out=tfplan

apply:hprod:
  extends: .terraform_base
  variables:
    ORG_ENV: hprod
  script:
    - terraform apply tfplan
  when: manual
  environment: hprod
```

Chaque job utilise un **prefix GCS distinct** (`apigee/org/hprod`, `apigee/org/pprod`, etc.), garantissant l'isolation complète des states.

### Paramètres qui varient entre organisations

Les paramètres suivants sont typiquement différents d'une organisation à l'autre et doivent être définis dans chaque `.tfvars` :

- `project_id`
- `display_name` / `description`
- `apigee_services` (certaines organisations peuvent ne pas nécessiter tous les services)
- `retention` (les environnements de prod peuvent avoir une rétention plus longue)
- `billing_type` (si la contractualisation diffère)

---

## 8. Services GCP activés

Le module `apigee_services` active les APIs nécessaires avant la création de l'organisation. Le module utilise `google_project_service` avec `disable_on_destroy = false` pour éviter toute désactivation accidentelle.

| Service | Utilité |
|---|---|
| `apigee.googleapis.com` | API principale Apigee |
| `apigeeconnect.googleapis.com` | Connexion MART entre Runtime Plane et Management Plane |
| `monitoring.googleapis.com` | Export des métriques Apigee vers Cloud Monitoring |
| `cloudresourcemanager.googleapis.com` | Gestion des ressources GCP par Terraform |
| `pubsub.googleapis.com` | Export des logs vers Pub/Sub (pipeline → SIEM on-premises) |

> D'autres services peuvent être ajoutés selon les besoins (ex. `clouddns.googleapis.com`, `certificatemanager.googleapis.com`) sans impact sur l'organisation Apigee elle-même.

---

## 9. Contraintes & points d'attention

### Immuabilité de certains paramètres

Les champs suivants **ne peuvent pas être modifiés** après la création de l'organisation sans recréation complète (destroy + apply) :

- `runtime_type`
- `billing_type`
- `api_consumer_data_location`

Toute tentative de modification entraîne une erreur de l'API Apigee. Planifier ces valeurs avec soin avant le premier `apply`.

### Endpoint régional

L'utilisation de `https://eu-apigee.googleapis.com/v1/` comme `apigee_custom_endpoint` dans le provider Google est **obligatoire** pour s'assurer que les appels d'API de gestion transitent par l'infrastructure européenne de Google, en cohérence avec les exigences de résidence des données.

```hcl
# providers.tf
provider "google" {
  apigee_custom_endpoint = var.apigee_custom_endpoint
}
```

### Délai de provisionnement

La création d'une organisation Apigee Hybrid prend typiquement **10 à 20 minutes**. Le provider attend la completion de l'opération longue — ne pas interrompre le pipeline pendant cette phase.

### Dépendance avec le Runtime Plane

Ce repo ne gère que le Management Plane (GCP). Le déploiement du Runtime Plane (Helm charts via ArgoCD) doit intervenir **après** la création de l'organisation et des environments (repo séparé), car `overrides.yaml` nécessite l'`org_name` et les noms d'environments comme paramètres d'entrée.

---

## 10. Références

- [Documentation Apigee Hybrid — Architecture](https://cloud.google.com/apigee/docs/hybrid/latest/what-is-hybrid)
- [Resource `google_apigee_organization` — Terraform Registry](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/apigee_organization)
- [Apigee Hybrid — Installation overview](https://cloud.google.com/apigee/docs/hybrid/latest/install-overview)
- [Résidence des données Apigee](https://cloud.google.com/apigee/docs/api-platform/get-started/data-residency)
- [Repo environments & environment groups](../002-Terraform-Envgroups/README.md) *(lien relatif — à adapter)*
- [Repo ArgoCD / Runtime Plane](../003-ArgoCD-Runtime/README.md) *(lien relatif — à adapter)*

