# Runbook — Passage de 1 à 2 clusters

Étendre le déploiement Apigee du setup mono-cluster (`cluster-A`) à un
setup bi-cluster (`cluster-A` + `cluster-B`).

## Ordre des opérations

Le passage à 2 clusters se fait en **4 phases indépendantes**. Ne pas
toucher à la phase suivante tant que la précédente n'est pas validée.

```
Phase 1 : Préparation cluster-B  (plateforme, hors ArgoCD)
Phase 2 : Stack plateforme Apigee sur cluster-B  (AppSets 01-03)
Phase 3 : Cassandra multi-DC  → runbook dédié cassandra-phase2.md
Phase 4 : Tenants étendus à cluster-B  (fichiers generator)
```

## Phase 1 — Préparation cluster-B

**Hors GitOps Apigee**, responsabilité plateforme :

- [ ] cluster-B provisionné sur ROKS
- [ ] cluster-B connecté à ArgoCD : visible dans
      `Settings → Clusters → cluster-B`
- [ ] Composants plateforme présents sur cluster-B (identiques à cluster-A) :
      cert-manager, External Secrets Operator, Traefik, Kyverno
- [ ] `ClusterSecretStore vault-<appUID>` disponible sur cluster-B
- [ ] Route OCP pour Apigee configurable par l'équipe réseau

**Test de validation** :

```bash
# Vérifier qu'un test ExternalSecret fonctionne sur cluster-B
kubectl --context cluster-B apply -f - << 'EOF'
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: test-vault-access
  namespace: default
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: vault-ap43591
  target:
    name: test-vault-access
  data:
    - secretKey: test
      remoteRef:
        key: secret/ap43591/apigee/_test
        property: hello
EOF

# Doit passer Ready=True
kubectl --context cluster-B get externalsecret test-vault-access
```

## Phase 2 — Stack plateforme Apigee sur cluster-B

### MR à faire

Modifier **4 AppSets** en décommentant la ligne `cluster-B` :

- [ ] `argo/manifests/01-ns-appset.yaml`
- [ ] `argo/manifests/02-platform-crds-appset.yaml`
- [ ] `argo/manifests/03-platform-controller-appset.yaml`

Exemple de modification :

```yaml
generators:
  - list:
      elements:
        - cluster: cluster-A
        - cluster: cluster-B    # ← décommenter
```

Créer le fichier de values spécifique cluster-B :

- [ ] `values/platform/controller/clusters/values-cluster-B.yaml`
      (copier cluster-A et ajuster `cluster.name`, `cluster.region`,
      `nodeSelector`…)

### Review

- [ ] Lead Apigee
- [ ] Plateforme (validation cluster-B prêt)

### Après merge

Surveiller dans l'ordre :
1. `apigee-ns-cluster-B` (wave 0) → Synced
2. `apigee-crds-cluster-B` (wave 5) → Synced
3. `apigee-controller-cluster-B` (wave 10) → Synced, controller pod Running

**NE PAS encore toucher aux tenants.** Ils ne doivent pas se déployer
sur cluster-B tant que Cassandra multi-DC n'est pas en place.

## Phase 3 — Cassandra multi-DC

→ **Runbook dédié** : `docs/cassandra-phase2.md`

Cette phase est la plus sensible. Elle se fait en 5 étapes dont 2
manuelles (`nodetool rebuild`, `nodetool repair`). Ne pas démarrer si
vous n'avez pas au moins 4 à 8h de fenêtre.

## Phase 4 — Extension des tenants

Une fois Cassandra multi-DC validé (`nodetool status` = 6 nodes UN),
les tenants peuvent étendre leur présence à cluster-B.

### Étape 4.1 — Décommenter cluster-B dans les AppSets tenants

MR modifiant **4 AppSets** :

- [ ] `argo/manifests/05-tenant-secrets-appset.yaml`
- [ ] `argo/manifests/06-tenant-ingress-appset.yaml`
- [ ] `argo/manifests/07-tenant-env-appset.yaml`
- [ ] `argo/manifests/08-tenant-exposure-appset.yaml`

Même modification : décommenter `- cluster: cluster-B`.

**Rien ne se passe encore côté tenant** car le selector filtre sur
`targetClusters` propre à chaque tenant.

### Étape 4.2 — Ajouter cluster-B aux tenants souhaités

Pour chaque tenant que vous voulez étendre, MR modifiant son generator :

```yaml
# argo/generators/tenants/<tenant>.yaml
targetClusters:
  - cluster-A
  - cluster-B    # ← ajout
```

Pour la prod, augmenter aussi la réplication Cassandra dans son
generator :

```yaml
cassandraReplication:
  dc-1: 3
  dc-2: 3
```

### Étape 4.3 — Values cluster-B spécifiques (si besoin)

- [ ] `values/tenants/<tenant>/clusters/values-<tenant>-cluster-B.yaml`

### Ordre recommandé des tenants

1. Commencer par **un tenant non-prod** (dev ou test) — vérifier que
   les Apps se créent bien sur cluster-B.
2. Puis un tenant de **validation** (ex: prod-sandbox si existant).
3. Enfin les **tenants prod** — un par un, avec observation entre chaque.

### Validation

Par tenant étendu :

```bash
# Pods runtime sur les 2 clusters
kubectl --context cluster-A -n apigee get pods -l apigee.cloud.google.com/tenant=<tenant>
kubectl --context cluster-B -n apigee get pods -l apigee.cloud.google.com/tenant=<tenant>

# Health côté Apigee (via un test API)
curl https://<host>/healthz   # doit répondre 200 quel que soit le cluster qui sert
```

## Rollback

### Rollback phase 2 (plateforme cluster-B)

Safe. Recommenter `cluster-B` dans les AppSets → ArgoCD supprime les
ressources plateforme de cluster-B. Cassandra n'est pas touchée si la
phase 3 n'a pas été faite.

### Rollback phase 3 (Cassandra)

Voir `cassandra-phase2.md` § Rollback.

### Rollback phase 4 (tenants)

- Si aucune donnée écrite via cluster-B : revert du generator suffit.
- Si cluster-B a servi du trafic : nettoyer Cassandra
  (`ALTER KEYSPACE` pour retirer `dc-2:3` d'abord) avant de retirer
  le DC.

## Points d'attention

- **Jamais d'extension tenant prod avant validation d'un tenant non-prod.**
- **Pendant la phase 3**, les tenants non-prod peuvent continuer à
  tourner en mono-DC (dc-1 uniquement) sans impact.
- **Latence inter-cluster** : Cassandra multi-DC en async = latence
  acceptée. Vérifier la latence inter-cluster-A/B < 50ms sinon les
  performances Apigee peuvent dégrader.
