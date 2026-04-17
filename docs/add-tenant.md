# Runbook — Ajouter un nouveau tenant Apigee

Procédure pour onboarder un nouvel environnement Apigee (= un tenant).

## Questions à se poser AVANT de démarrer

1. **Ce tenant est-il prod ou non-prod ?**
   - Non-prod → probablement en `mode: shared` (gateway mutualisée `_infra-nonprod`)
   - Prod → en `mode: dedicated` (gateway propre)
2. **Sur quels clusters ?**
   - Phase 1 : tout sur `cluster-A`
   - Phase 2 : HA possible en listant `[cluster-A, cluster-B]` dans `targetClusters`
3. **Combien de hostnames ?**
   - Typiquement 1 externe + 1 interne en prod
4. **L'équipe sécurité a-t-elle provisionné les paths Vault ?**

## Checklist de la MR d'onboarding

### A. Pré-requis externes (à faire AVANT la MR)

- [ ] **Équipe GCP** : Service Account GCP créé avec les rôles :
      `roles/apigee.synchronizerManager`, `roles/apigee.analyticsAgent`
- [ ] **Équipe sécu** : paths Vault provisionnés sous
      `secret/<appUID>/apigee/<tenant>/` avec les clés :
      - `sa-synchronizer.json` (contenu du SA GCP synchronizer)
      - `sa-udca.json`
      - `sa-mart.json`
      - `sa-metrics.json`
      - `tls/internal` avec les propriétés `certificate` et `private_key`
- [ ] **Équipe DNS** : hostnames réservés, CNAME vers l'ingress F5 plateforme
- [ ] **Équipe PKI** : cert interne émis pour le SAN attendu par
      `exposition.serversTransport.serverName`
- [ ] **Équipe réseau** : Route OCP créée pointant vers le Service cible
      (le nom du Service est connu par convention :
      `apigee-ingress-<tenant>` pour dedicated, `apigee-ingress-nonprod` pour shared)

### B. Fichiers à créer dans cette MR

**Obligatoires :**

- [ ] `argo/generators/tenants/<tenant>.yaml`
      Copier le template le plus proche (`dev.yaml` pour non-prod,
      `prod-finance.yaml` pour prod) et adapter.

- [ ] `values/tenants/<tenant>/values-<tenant>.yaml`
      Surcharges par défaut pour ce tenant (ressources, PDB, quotas).

**Optionnels :**

- [ ] `values/tenants/<tenant>/clusters/values-<tenant>-<cluster>.yaml`
      Uniquement si surcharges spécifiques à un cluster (nodeSelector,
      tolerations particulières).

**Rien d'autre à modifier.** Les AppSets existants détectent
automatiquement les nouveaux fichiers dans `generators/tenants/` et
génèrent les Applications correspondantes.

### C. Validation locale avant le push

```bash
# 1. Lint du chart avec les values du nouveau tenant
helm lint charts/apigee-tenant \
  --values values/tenants/values-common.yaml \
  --values values/tenants/<tenant>/values-<tenant>.yaml

# 2. Rendu complet, pour vérifier à l'œil
helm template apigee-<tenant> charts/apigee-tenant \
  --values values/tenants/values-common.yaml \
  --values values/tenants/<tenant>/values-<tenant>.yaml \
  --set tenant.name=<tenant> \
  --set tenant.cluster=cluster-A \
  --set tenant.appUID=ap43591 \
  | less

# 3. Validation Kubernetes via kubeconform
helm template ... | kubeconform \
  -schema-location default \
  -schema-location 'crds/{{.ResourceKind}}.json' \
  -strict -summary
```

La CI GitLab refait ces 3 étapes automatiquement — voir `.gitlab-ci.yml`.

### D. Review de la MR

- [ ] Lead Apigee
- [ ] Si tenant prod : +1 ops ou SRE
- [ ] Si ajout cross-cluster : +1 plateforme

### E. Après le merge

1. Surveiller dans ArgoCD que les nouvelles Applications se créent :
   - `apigee-secrets-<tenant>-cluster-A`
   - `apigee-ingress-<tenant>-cluster-A` (si dedicated)
   - `apigee-env-<tenant>-cluster-A`
   - `apigee-exposure-<tenant>-cluster-A`

2. Vérifier la santé des ressources :
   ```bash
   kubectl -n apigee get externalsecret,apigeeenvironment,ingress \
     -l apigee.cloud.google.com/tenant=<tenant>
   ```

3. Test fonctionnel :
   ```bash
   curl -v https://<host>/healthz
   ```

4. Déclarer l'env côté control plane Apigee (UI GCP ou apigee-api) —
   cette partie n'est pas GitOps, elle relève de la gestion Apigee pure.

## Retrait d'un tenant

Voir `tenant-removal.md` — **ce n'est pas juste supprimer le fichier
generator**, il y a un nettoyage Cassandra à prévoir.
