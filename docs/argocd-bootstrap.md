# Runbook — Bootstrap ArgoCD

Procédure de **première installation** du déploiement Apigee Hybrid
via ArgoCD. À faire une seule fois par instance ArgoCD.

## Pré-requis

- [ ] Instance ArgoCD déployée par la plateforme, URL connue :
      `https://argocd-<id>-<env>-<instance-id>.data.cloud.net.intra`
- [ ] cluster-A connecté à ArgoCD (visible dans `Settings → Clusters`)
- [ ] Namespace `argocd-<id>-apps` existant (c'est LÀ que les Apps seront créées)
- [ ] Accès UI ArgoCD avec droits de créer une Application
- [ ] Ce dépôt GitLab connecté à l'instance ArgoCD
      (via l'UI `Settings → Repositories`, ou via connexion préalable
      faite par la plateforme)

## Étape 1 — Créer la Root App via l'UI

La première Application (`apigee-root-app`) est la seule qui se crée
manuellement. Toutes les autres sont générées par ArgoCD.

1. Dans l'UI ArgoCD, cliquer sur `+ NEW APP`.
2. Passer en mode `EDIT AS YAML` (en haut à droite).
3. Coller le contenu de `argo/manifests/my-root-app.yaml`.
4. **Préfixer le nom avec le namespace de l'instance :**
   ```
   name: argocd-<id>-apps/apigee-root-app
   ```
   Ce préfixe est dû au setup "App in any namespace" de la plateforme.
   Il doit être présent **uniquement dans l'UI**, pas dans le fichier Git.
5. Vérifier que les champs suivants correspondent à votre environnement :
   - `spec.source.repoURL` — URL GitLab de ce repo
   - `spec.source.targetRevision` — branche (hprd, prd)
   - `spec.source.path` — `argo/manifests`
6. Cliquer `CREATE`.

## Étape 2 — Premier sync

1. Une fois créée, la root App apparaît en `OutOfSync`.
2. Cliquer `SYNC` → `SYNCHRONIZE`.
3. ArgoCD lit `argo/manifests/kustomization.yaml` et crée les 8 AppSets.
4. Les AppSets génèrent à leur tour les Applications concrètes par
   cluster et par tenant, selon les sync-waves.

## Étape 3 — Vérification de l'ordre de sync

Observer l'ordre des objets en `Syncing` / `Synced` :

```
Wave 0   → apigee-ns-cluster-A
Wave 5   → apigee-crds-cluster-A
Wave 10  → apigee-controller-cluster-A
Wave 15  → apigee-cassandra  (attendre "Healthy" — peut prendre 10-20 min)
Wave 25  → apigee-secrets-<tenant>-cluster-A    (tous les tenants en parallèle)
Wave 28  → apigee-ingress-<tenant>-cluster-A    (tenants dedicated + infra)
Wave 30  → apigee-env-<tenant>-cluster-A        (tous les tenants standards)
Wave 35  → apigee-exposure-<tenant>-cluster-A   (tous les tenants)
```

**Points d'arrêt possibles (normaux) :**

- **Cassandra wave 15 bloque longtemps.** Les pods initialisent les
  keyspaces Apigee et démarrent le Cassandra cluster. Attendre que
  `nodetool status` montre 3 nodes UN avant de conclure à un problème.
- **Secrets wave 25 en `Missing`.** Vérifier que les paths Vault existent
  côté plateforme (cf. pré-requis de la MR tenant).
- **ApigeeEnvironment en `Progressing` longtemps.** Le synchronizer doit
  atteindre le control plane Apigee (GCP) — vérifier les logs du pod
  `apigee-synchronizer-<env>-*`.

## Étape 4 — Validation de santé

```bash
# Vérifier que tous les pods du namespace apigee sont Running
kubectl --context cluster-A -n apigee get pods

# Vérifier l'état des CR Apigee
kubectl --context cluster-A -n apigee get apigeeorganization
kubectl --context cluster-A -n apigee get apigeedatastore
kubectl --context cluster-A -n apigee get apigeeenvironment
kubectl --context cluster-A -n apigee get apigeeenvgroup

# Tous doivent être State=running (ou équivalent)
```

## Étape 5 — Test fonctionnel

Appeler un endpoint Apigee depuis l'extérieur :

```bash
# Depuis un poste interne (ou via VPN)
curl -v https://api-dev.mondomaine.com/healthz
# Attendu : 200 OK ou la réponse de l'API déployée
```

Si échec :
1. Vérifier la Route OCP côté équipe réseau.
2. Vérifier que le Service `apigee-ingress-*` est bien exposé (ClusterIP).
3. Vérifier que l'ApigeeEnvGroup porte bien le host dans ses routingRules.

## Troubleshooting fréquent

### "CRD not found" lors de la wave 30

La wave 5 (CRDs) n'est pas allée jusqu'au bout. Forcer un re-sync de
`apigee-crds-cluster-A` avec `Replace=true` activé.

### "Secret not found: apigee-synchronizer-svc-account-..."

Le ExternalSecret est en erreur. Diagnostiquer :

```bash
kubectl --context cluster-A -n apigee get externalsecret
kubectl --context cluster-A -n apigee describe externalsecret apigee-synchronizer-<tenant>
```

Causes fréquentes :
- Path Vault manquant
- `ClusterSecretStore` pas accessible depuis ce namespace
  (vérifier `spec.provider.vault.namespace` côté plateforme)
- Propriété JSON pas au bon nom dans Vault

### Pods Cassandra en CrashLoopBackOff

Vérifier :
- PVCs bien provisionnés (`kubectl get pvc -n apigee`)
- Secret `apigee-cassandra-auth` présent
- StorageClass ROKS opérationnelle

## Après le bootstrap

Une fois tout `Synced` et `Healthy`, ne plus rien créer via l'UI ArgoCD.
Tout passe désormais par des MR Git (cf. `add-tenant.md`,
`extending-to-two-clusters.md`).
