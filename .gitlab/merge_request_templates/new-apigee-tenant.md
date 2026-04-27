# Onboarding d'un nouveau tenant Apigee

## Contexte

- **Nom du tenant** :
- **appUID** :
- **Environnement plateforme** (hprd/prd) :
- **Clusters cibles** : [ ] cluster-A  [ ] cluster-B
- **Mode IngressGateway** : [ ] dedicated  [ ] shared → gateway référencée :
- **Hostnames exposés** :
  -
- **Owner applicatif** (équipe, ticket d'origine) :
- **Date cible de mise en prod** :

## Pré-requis externes

À valider **AVANT le merge** (cocher au fur et à mesure, joindre les
tickets en commentaire) :

- [ ] **Équipe GCP** : Service Account créé, rôles Apigee attribués
      Ticket / référence :
- [ ] **Équipe sécu** : paths Vault provisionnés sous
      `secret/<appUID>/apigee/<tenant>/` avec toutes les clés requises
      (`sa-synchronizer.json`, `sa-udca.json`, `sa-mart.json`,
      `sa-metrics.json`, `tls/internal` avec `certificate` + `private_key`)
      Ticket / référence :
- [ ] **Équipe DNS** : hostnames réservés, CNAME en place
      Ticket / référence :
- [ ] **Équipe PKI** : cert interne émis, SAN aligné avec
      `exposition.serversTransport.serverName`
      Ticket / référence :
- [ ] **Équipe réseau** : Route OCP prête à être créée vers le Service
      cible (`apigee-ingress-<tenant>` ou `apigee-ingress-nonprod`)
      Ticket / référence :

## Fichiers ajoutés/modifiés dans cette MR

- [ ] `argo/generators/tenants/<tenant>.yaml` (nouveau)
- [ ] `values/tenants/<tenant>/values-<tenant>.yaml` (nouveau)
- [ ] `values/tenants/<tenant>/clusters/values-<tenant>-<cluster>.yaml` (optionnel)
- [ ] Rien d'autre (les AppSets n'ont PAS besoin d'être modifiés)

## Validation locale

- [ ] `helm lint charts/apigee-tenant --values ...` passe sans erreur
- [ ] `helm template` rend un YAML cohérent (vérifié à l'œil)
- [ ] `kubeconform` valide les ressources K8s natives
- [ ] Pipeline CI vert (tous les stages)

## Review

Reviewers requis (marquer « approuvé » dans un commentaire) :

- [ ] Lead Apigee : @___
- [ ] Ops/SRE (obligatoire si tenant prod) : @___
- [ ] Sécu (si paths Vault critiques) : @___

## Plan post-merge

- [ ] Vérifier dans ArgoCD que les 4 Applications du tenant apparaissent
      (secrets, ingress si dedicated, env, exposure)
- [ ] Chaque Application doit atteindre `Synced` + `Healthy`
- [ ] Test fonctionnel : `curl -v https://<host>/healthz` → 200 OK
- [ ] Déclarer l'env côté control plane Apigee (UI GCP)
- [ ] Documenter le tenant dans le wiki équipe

## Rollback

- Revert de la MR si pas encore en prod
- Si déjà en prod : voir `docs/tenant-removal.md`

---
/label ~apigee ~tenant-onboarding
