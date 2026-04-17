# Runbook — Retirer un tenant Apigee

> ⚠️ **Ne JAMAIS supprimer un tenant en supprimant simplement son fichier
> `argo/generators/tenants/<tenant>.yaml`.** Le nettoyage Cassandra doit
> être fait manuellement AVANT, sinon les keyspaces gardent des
> métadonnées orphelines pour toujours.

## Pré-requis

- [ ] Accord de l'owner applicatif du tenant (ticket, mail archivé)
- [ ] Vérification qu'aucun trafic ne passe sur le tenant depuis 7 jours
      (dashboard Apigee Analytics, logs Traefik)
- [ ] Backup Cassandra récent disponible
- [ ] Fenêtre de maintenance planifiée

## Procédure complète — 5 étapes

### Étape 1 — Arrêter le trafic entrant

**MR de pré-retrait** (optionnelle mais recommandée) :

Vider la liste `exposition.hosts` dans le generator du tenant. Cela
supprime les Ingress Traefik → le tenant devient injoignable depuis
l'extérieur sans être détruit.

```yaml
# argo/generators/tenants/<tenant>.yaml
exposition:
  ingressClass: traefik
  hosts: []    # ← vidé
  targetServiceName: ...
```

Observer 24 à 48h → vérifier qu'aucune alerte applicative ne remonte.

### Étape 2 — Retirer le tenant de la réplication Cassandra (SI multi-DC)

**Uniquement si le tenant tournait sur plusieurs DC.** En phase 1 mono-DC
cette étape ne s'applique pas.

Côté Apigee, le controller gère la réplication **par keyspace**, pas
par tenant. Donc retirer un tenant ne demande PAS d'`ALTER KEYSPACE` —
les données applicatives du tenant restent dans les keyspaces partagés
jusqu'au nettoyage Cassandra (étape 4).

### Étape 3 — Retirer les ressources K8s du tenant (GitOps)

**MR de retrait** :

1. **Supprimer le fichier generator** :
   ```
   rm argo/generators/tenants/<tenant>.yaml
   ```
2. **Supprimer le dossier values** :
   ```
   rm -rf values/tenants/<tenant>/
   ```

**Après merge** :

ArgoCD détecte la disparition du generator. Les 4 AppSets tenants
(`secrets`, `ingress`, `env`, `exposure`) ne génèrent plus d'Application
pour ce tenant, et **suppriment** celles qui existaient.

**Attention `syncPolicy.automated.prune`** :
- AppSet 05 (secrets)  : `prune: true` → Secrets supprimés ✓
- AppSet 06 (ingress)  : `prune: true` → IngressGateway supprimée ✓
- AppSet 07 (env)      : `prune: false` ⚠️ — ApigeeEnvironment NON supprimé automatiquement
- AppSet 08 (exposure) : `prune: true` → Ingress Traefik supprimé ✓

Le `prune: false` sur l'AppSet 07 est délibéré : on ne veut pas qu'une
erreur de generator (ex. typo dans le nom du tenant) supprime par
inadvertance un ApigeeEnvironment de prod.

### Étape 4 — Supprimer manuellement l'ApigeeEnvironment

Une fois la MR étape 3 mergée, supprimer explicitement :

```bash
# Par cluster où le tenant tournait
for cluster in cluster-A cluster-B; do
  kubectl --context $cluster -n apigee delete apigeeenvironment <apigeeEnv>
  kubectl --context $cluster -n apigee delete apigeeenvgroup <apigeeEnvGroup> \
    || echo "Si l'envgroup est partagé, le laisser vivre"
done
```

Le controller Apigee nettoie derrière : pods runtime, synchronizer,
UDCA propres au tenant sont terminés.

### Étape 5 — Nettoyage Cassandra (optionnel mais recommandé)

Les keyspaces Apigee contiennent encore des données propres à l'env
supprimé (proxies API déployés, KVM, caches…). Ces données ne sont pas
nettoyées automatiquement — elles deviennent des **tombstones** jusqu'à
expiration TTL (parfois plusieurs années).

Si le volume est problématique :

```bash
# Depuis un pod Cassandra
kubectl -n apigee exec -it apigee-cassandra-default-0 -- bash

# Dans cqlsh (auth requise — mot de passe dans Secret apigee-cassandra-auth)
cqlsh -u apigee -p <password>

# Vérifier les keyspaces
DESCRIBE KEYSPACES;

# Supprimer les données du tenant retiré (exemple pour un keyspace)
USE cache_<orgname>_hybrid;
DELETE FROM cache_entries WHERE environment = '<apigeeEnv>';
```

**⚠️ Ces commandes sont destructives.** Les tester en non-prod d'abord,
et idéalement les faire valider par un DBA Cassandra.

### Étape 6 — Nettoyage externe

À faire en parallèle :

- [ ] **Équipe sécu** : archiver / supprimer les paths Vault
      `secret/<appUID>/apigee/<tenant>/`
- [ ] **Équipe GCP** : désactiver / supprimer les Service Accounts
      GCP associés
- [ ] **Équipe DNS** : libérer les hostnames (CNAME)
- [ ] **Équipe réseau** : supprimer la Route OCP
- [ ] **Côté control plane Apigee (GCP)** : supprimer l'environnement
      et l'envgroup dans l'org Apigee (UI Apigee ou API)

## Cas particulier — retirer un tenant `_infra-*`

Un tenant infra porte une IngressGateway **partagée** par d'autres
tenants. Avant de le retirer :

1. **Migrer tous les tenants `mode: shared` qui pointent vers cette
   gateway** vers une autre gateway (infra dédié ou créer une nouvelle
   infra).
2. S'assurer qu'aucun `sharedGatewayName` ne référence plus cette
   gateway.
3. Seulement alors retirer le tenant infra.

Sinon : les tenants orphelins resteront en `Degraded` car leur
ApigeeEnvGroup référence une gateway inexistante.

## Validation du retrait

```bash
# Aucune ressource ne doit plus porter le label du tenant
kubectl -n apigee get all,externalsecret,ingress,networkpolicy \
  -l apigee.cloud.google.com/tenant=<tenant>
# Sortie attendue : "No resources found"

# ApigeeEnvironment absent
kubectl -n apigee get apigeeenvironment <apigeeEnv>
# Sortie attendue : "Error from server (NotFound)"

# ArgoCD : aucune Application n'apparaît pour ce tenant
# Filtrer dans l'UI par le label apigee.cloud.google.com/tenant
```
