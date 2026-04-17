# Apigee Hybrid — Dépôt GitOps

Dépôt de déploiement (CD) pour Apigee Hybrid sur ROKS, piloté par ArgoCD.

## Vue d'ensemble

Ce dépôt déploie Apigee Hybrid en deux couches :

1. **Couche plateforme** (une fois par cluster) : CRDs Apigee, controller,
   Cassandra, telemetry.
2. **Couche tenant** (par environnement Apigee) : `ApigeeEnvironment`,
   `ApigeeEnvGroup`, IngressGateway, ExternalSecrets, Ingress Traefik.

**Phase 1 — démarrage** : un seul cluster (`cluster-A`)
**Phase 2 — extension** : ajout de `cluster-B` + Cassandra multi-DC
(voir `docs/cassandra-phase2.md` et `docs/extending-to-two-clusters.md`)

## Arborescence

```
.
├── README.md                              — ce fichier
├── .gitlab-ci.yml                         — pipeline CI (lint, validate, argocd)
├── .gitlab/merge_request_templates/       — templates MR (tenant, Cassandra)
│
├── argo/
│   ├── manifests/                         — ArgoCD Applications/ApplicationSets
│   │   ├── kustomization.yaml             — orchestration
│   │   ├── my-root-app.yaml               — root App (créée dans l'UI)
│   │   ├── 01-ns-appset.yaml              — wave 0  : namespace apigee
│   │   ├── 02-platform-crds-appset.yaml   — wave 5  : CRDs Apigee
│   │   ├── 03-platform-controller-appset  — wave 10 : controller + telemetry
│   │   ├── 04-cassandra-app.yaml          — wave 15 : Cassandra (App dédiée)
│   │   ├── 05-tenant-secrets-appset.yaml  — wave 25 : ExternalSecrets
│   │   ├── 06-tenant-ingress-appset.yaml  — wave 28 : IngressGateway dedicated
│   │   ├── 07-tenant-env-appset.yaml      — wave 30 : ApigeeEnvironment + EnvGroup
│   │   └── 08-tenant-exposure-appset.yaml — wave 35 : Ingress Traefik + extras
│   └── generators/tenants/                — un fichier YAML plat par tenant
│       ├── _infra-nonprod.yaml            — tenant technique, gateway mutualisée
│       ├── dev.yaml                       — mode shared
│       ├── test.yaml                      — mode shared
│       └── prod-finance.yaml              — mode dedicated, HTTPS end-to-end
│
├── charts/
│   ├── apigee-platform/                   — namespace + CRDs + controller + telemetry
│   ├── apigee-cassandra/                  — ApigeeDatastore, pilotage phase 1 → 2
│   └── apigee-tenant/                     — 4 sous-rendus via render.only :
│                                            externalsecrets | ingressgateway
│                                            | apigee-env    | exposure
│
├── values/
│   ├── platform/
│   │   ├── namespace/values-common.yaml
│   │   ├── crds/values-common.yaml
│   │   ├── controller/values-common.yaml + clusters/values-cluster-A.yaml
│   │   ├── telemetry/values-common.yaml
│   │   └── cassandra/
│   │       ├── values-common.yaml
│   │       ├── values-topology.yaml       — ⚠️ pilote mono-DC → multi-DC
│   │       └── values-dc1.yaml
│   └── tenants/
│       ├── values-common.yaml             — paramètres partagés par tous
│       ├── _infra-nonprod/...
│       ├── dev/values-dev.yaml
│       ├── test/values-test.yaml
│       └── prod-finance/
│           ├── values-prod-finance.yaml
│           └── clusters/values-prod-finance-cluster-A.yaml
│
└── docs/
    ├── argocd-bootstrap.md                — création root App, première sync
    ├── add-tenant.md                      — procédure onboarding tenant
    ├── extending-to-two-clusters.md       — passage 1 → 2 clusters
    ├── cassandra-phase2.md                — runbook critique multi-DC
    └── tenant-removal.md                  — retrait propre d'un tenant
```

## Sync-waves ArgoCD

| Wave | Objet | Source |
|------|-------|--------|
| 0 | Namespace `apigee` (label `appUID`) | AppSet 01 |
| 5 | CRDs Apigee Hybrid | AppSet 02 |
| 10 | Controller Apigee + telemetry + `ApigeeOrganization` | AppSet 03 |
| 15 | Cassandra (`ApigeeDatastore`) | App 04 |
| 25 | ExternalSecrets tenant (SA GCP, TLS, CA) | AppSet 05 |
| 28 | IngressGateway dedicated (si applicable) | AppSet 06 |
| 30 | `ApigeeEnvironment` + `ApigeeEnvGroup` | AppSet 07 |
| 35 | Ingress Traefik + ServersTransport + NetworkPolicies | AppSet 08 |

## Interfaces avec la plateforme

Ces composants sont **fournis par la plateforme ROKS**, nous les consommons :

- `cert-manager` — pour le cert TLS externe (`ingress-tls` dans namespace `traefik`)
- `External Secrets Operator` + `ClusterSecretStore vault-<appUID>` — accès Vault
- `Traefik Ingress Controller` — routage (on pose des `Ingress` + `ServersTransport`)
- `Kyverno` — policy appliquée au namespace via le label `appUID`
- **Route OpenShift** — créée par l'équipe réseau, pointe vers notre Service
- **F5 LoadBalancer** — expose le Traefik plateforme à l'extérieur

Nous **ne déployons pas** ces composants — notre périmètre commence à
l'`Ingress` Traefik dans notre namespace et descend jusqu'à Cassandra.

## Démarrage rapide

1. Lire `docs/argocd-bootstrap.md`
2. Créer la root App via l'UI ArgoCD
3. Surveiller la sync par waves
4. Pour ajouter un tenant : lire `docs/add-tenant.md` et utiliser la MR type
5. Pour passer à 2 clusters : lire `docs/extending-to-two-clusters.md`

## Points de vigilance

- **Cassandra `prune: false`** — ArgoCD ne doit JAMAIS supprimer
  automatiquement les StatefulSets ou les PVCs Cassandra.
- **CRDs Apigee `prune: false`** — supprimer une CRD supprime toutes
  ses CR en cascade.
- **Namespace `apigee` `prune: false`** — supprimer le namespace supprime tout.
- **Tenants infra `_*`** — portent des ressources partagées, retirer
  en dernier.
- **Passage multi-DC Cassandra** — lire `docs/cassandra-phase2.md`
  **en entier** avant toute action. Ne jamais improviser.

## Contribution

Toute modification passe par une MR avec pipeline CI vert. Les MR
critiques (Cassandra, CRDs, ajout de cluster) utilisent un template
dédié dans `.gitlab/merge_request_templates/`.
