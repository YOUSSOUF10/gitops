# Runbook — Cassandra passage en multi-DC (phase 1 → phase 2)

> ⚠️ **Document critique.** Lire en entier AVANT de toucher à quoi que ce soit.
> Une étape sautée ou faite dans le désordre = perte de données ou indisponibilité.

## Objectif

Étendre Cassandra depuis le setup initial **mono-DC** (3 nodes sur cluster-A)
vers un setup **multi-DC** (3 nodes sur cluster-A + 3 nodes sur cluster-B),
sans interruption de service Apigee.

## Pré-requis — à valider AVANT de commencer

- [ ] Cassandra phase 1 stable depuis au moins 2 semaines
  (vérifier `nodetool status` : 3 nodes UN depuis longtemps)
- [ ] cluster-B provisionné et connecté à ArgoCD
- [ ] Namespace `apigee` existant sur cluster-B (wave 0 de l'AppSet ns passée)
- [ ] CRDs Apigee posées sur cluster-B (wave 5 passée)
- [ ] Controller Apigee Ready sur cluster-B (wave 10 passée)
- [ ] **Service cross-cluster créé par la plateforme** :
  - DNS interne `cassandra-seed.apigee.internal` resolvable depuis cluster-A et cluster-B
  - Pointe vers les pods Cassandra de cluster-A initialement
- [ ] Backup Cassandra à jour (snapshot + export vers GCS/S3)
- [ ] Fenêtre de maintenance planifiée (durée estimée : 4 à 8h selon volume)
- [ ] Au moins 2 opérateurs disponibles en parallèle (procédure non-solo)

## Vue d'ensemble

Le passage multi-DC se fait en **5 étapes** dont **2 manuelles** (nodetool)
entre des étapes GitOps. C'est précisément pour cela qu'on a choisi une App
dédiée pour Cassandra (pas d'AppSet) : on contrôle manuellement le rythme.

```
[Étape 1] Plateforme   : créer le Service cross-cluster pour les seeds
[Étape 2] GitOps MR #1 : activer multiRegion + ajouter DC2 (replication inchangée)
          ArgoCD sync  → 3 pods DC2 créés (VIDES)
[Étape 3] Manuel       : nodetool rebuild depuis DC2 → réplique les données
[Étape 4] GitOps MR #2 : augmenter keyspacesReplication {dc-1:3, dc-2:3}
          ArgoCD sync  → ALTER KEYSPACE sur tous les keyspaces Apigee
[Étape 5] Manuel       : nodetool repair -full → garantit la cohérence
```

## Étape 1 — Service cross-cluster (plateforme)

**Qui fait quoi :** l'équipe plateforme crée un Service/DNS interne qui permet
à un pod sur cluster-B de résoudre et atteindre les seeds Cassandra sur cluster-A.

Ce que **nous** vérifions avant de passer à l'étape 2 :

```bash
# Depuis un pod de test sur cluster-B
kubectl --context cluster-B run -it --rm test --image=busybox --restart=Never -- \
  nslookup cassandra-seed.apigee.internal

# Vérifier qu'on peut joindre le port Cassandra (9042) :
kubectl --context cluster-B run -it --rm test --image=busybox --restart=Never -- \
  nc -vz cassandra-seed.apigee.internal 9042
```

Si l'un des deux échoue : **STOP**, retour à l'équipe plateforme.

## Étape 2 — Activation multiRegion (GitOps, MR #1)

### Modifications à faire dans Git

**Fichier à modifier :** `values/platform/cassandra/values-topology.yaml`

```yaml
cassandra:
  multiRegion:
    enabled: true                              # false → true
    seedHost: "cassandra-seed.apigee.internal"  # vide → valeur

  datacenters:
    - name: dc-1
      cluster: cluster-A
      replicaCount: 3
      podAntiAffinity:
        type: required
      rack:
        name: ra-1
    # ↓ NOUVEAU bloc à ajouter ↓
    - name: dc-2
      cluster: cluster-B
      replicaCount: 3
      podAntiAffinity:
        type: required
      rack:
        name: ra-1

  # PAS ENCORE TOUCHER À keyspacesReplication !
  keyspacesReplication:
    dc-1: 3
```

**Fichier à créer :** `values/platform/cassandra/values-dc2.yaml`

```yaml
dc2:
  seedList:
    - apigee-cassandra-default-0.apigee-cassandra-default.apigee.svc.cluster.local
    - apigee-cassandra-default-1.apigee-cassandra-default.apigee.svc.cluster.local
    - apigee-cassandra-default-2.apigee-cassandra-default.apigee.svc.cluster.local
```

**Deuxième App Cassandra sur cluster-B** — créer `argo/manifests/04b-cassandra-app-clusterB.yaml` :

Copier `04-cassandra-app.yaml`, remplacer :
- `name: apigee-cassandra` → `name: apigee-cassandra-dc2`
- `destination.name: cluster-A` → `destination.name: cluster-B`
- Ajouter `values-dc2.yaml` dans `valueFiles` à la place de `values-dc1.yaml`

Ajouter la référence dans `argo/manifests/kustomization.yaml`.

### Review de la MR #1

**Reviewers obligatoires :**
- [ ] Lead Apigee/Cassandra
- [ ] Équipe plateforme (pour valider que le Service cross-cluster est stable)

### Merge et sync

1. Merger la MR
2. ArgoCD détecte et synchronise :
   - L'App `apigee-cassandra` sur cluster-A : met à jour le CR ApigeeDatastore
     (ajoute le bloc dc-2 mais ne crée rien sur cluster-A)
   - L'App `apigee-cassandra-dc2` sur cluster-B : crée le StatefulSet, 3 PVCs, 3 pods
3. **Attendre que les 3 pods DC2 soient Running** (peut prendre 10-20 min pour
   les premiers pulls + initialisation Cassandra)

### Vérification avant étape 3

```bash
# Statut sur cluster-B
kubectl --context cluster-B -n apigee get pods -l app=apigee-cassandra

# Statut Cassandra cluster-wide : TOUS les nodes doivent apparaître UN
kubectl --context cluster-A -n apigee exec apigee-cassandra-default-0 -- \
  nodetool status

# Sortie attendue :
# Datacenter: dc-1
# ================
# UN 10.x.x.x  dc-1
# UN 10.x.x.x  dc-1
# UN 10.x.x.x  dc-1
# Datacenter: dc-2
# ================
# UN 10.y.y.y  dc-2   ← les 3 nodes DC2 doivent être UN
# UN 10.y.y.y  dc-2
# UN 10.y.y.y  dc-2
```

**⚠️ À ce stade, les nodes DC2 sont UN mais VIDES.** Ils n'ont reçu aucune donnée.
Passer à l'étape 3 avant de toucher à la replication.

## Étape 3 — `nodetool rebuild` (MANUEL, critique)

Cette étape copie les données existantes depuis DC1 vers DC2. À faire
**sur chacun des 3 pods du DC2**, séquentiellement (pas en parallèle).

```bash
# Pour chaque pod DC2, un à la fois :
for i in 0 1 2; do
  echo "=== Rebuild pod apigee-cassandra-default-${i} sur DC2 ==="
  kubectl --context cluster-B -n apigee exec apigee-cassandra-default-${i} -- \
    nodetool rebuild -- dc-1
  # Attendre la fin (peut durer 1-4h par pod selon volume)
  # Vérifier nodetool netstats pour suivre la progression
done
```

**Pendant le rebuild** (sur un autre terminal) :

```bash
kubectl --context cluster-B -n apigee exec apigee-cassandra-default-0 -- \
  nodetool netstats | grep -i streaming
```

**Si un rebuild échoue** (timeout, erreur réseau) :
- Relancer la commande `nodetool rebuild -- dc-1` sur le même pod
- Cassandra reprend là où il s'était arrêté (streams atomiques)

### Validation avant étape 4

```bash
# Vérifier que les tailles de données sont cohérentes entre DC1 et DC2
kubectl --context cluster-A -n apigee exec apigee-cassandra-default-0 -- \
  nodetool status | head -20

# Chaque node dc-2 doit avoir une "Load" comparable à celle des nodes dc-1
# (à ±10%). Si Load=0 sur DC2, le rebuild n'a pas fonctionné.
```

## Étape 4 — Augmentation de la replication (GitOps, MR #2)

**Fichier à modifier :** `values/platform/cassandra/values-topology.yaml`

```yaml
  keyspacesReplication:
    dc-1: 3
    dc-2: 3         # ← AJOUT
```

### Merge et sync

1. Merger MR #2
2. ArgoCD met à jour le CR `ApigeeDatastore`
3. Le controller Apigee lance des `ALTER KEYSPACE` sur les 8 keyspaces Apigee
4. Opération rapide (quelques secondes) mais **bloquante** — s'assurer
   qu'aucune autre opération Cassandra ne tourne en parallèle

## Étape 5 — `nodetool repair` (MANUEL, critique)

Le `ALTER KEYSPACE` déclare la nouvelle réplication mais ne déplace pas les
données. Le `repair` force la synchronisation.

```bash
# Sur un pod de CHAQUE DC, séquentiellement
kubectl --context cluster-A -n apigee exec apigee-cassandra-default-0 -- \
  nodetool repair -full

kubectl --context cluster-B -n apigee exec apigee-cassandra-default-0 -- \
  nodetool repair -full
```

Durée : 30 min à 2h par DC. Peut tourner en parallèle des requêtes Apigee.

## Validation finale

- [ ] `nodetool status` montre 6 nodes UN répartis 3+3
- [ ] Tous les pods Apigee (runtime, synchronizer, udca) sur cluster-A et cluster-B
      sont Ready
- [ ] Latence API Apigee inchangée (ou meilleure) sur les 24h suivantes
- [ ] Dashboards Apigee sur Cloud Monitoring : pas d'erreurs 5xx sur la période

## En cas de problème

### Rollback en urgence (si étape 2 ou 3 échoue)

Rollback possible **tant que l'étape 4 n'est pas faite**.

1. MR de revert sur `values-topology.yaml` (remettre `enabled: false`)
2. Supprimer l'App `apigee-cassandra-dc2`
3. Supprimer manuellement les PVCs DC2 sur cluster-B :
   ```bash
   kubectl --context cluster-B -n apigee delete pvc -l app=apigee-cassandra
   ```

### Rollback après étape 4

**Beaucoup plus complexe.** Il faut d'abord `ALTER KEYSPACE` pour retirer dc-2
de la réplication sur TOUS les keyspaces, puis décommissionner les nodes DC2
un par un (`nodetool decommission`), puis seulement supprimer l'infra.

→ Si un problème survient après l'étape 4, **ne pas tenter un rollback
sauvage** : ouvrir un ticket avec le lead Cassandra.

## Ressources

- [Apigee Hybrid — Multi-region deployment](https://cloud.google.com/apigee/docs/hybrid/v1.14/multi-region)
- [Cassandra nodetool rebuild](https://cassandra.apache.org/doc/latest/cassandra/managing/tools/nodetool/rebuild.html)
