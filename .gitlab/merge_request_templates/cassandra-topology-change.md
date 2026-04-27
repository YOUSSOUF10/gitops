# Changement de topologie Cassandra

> ⚠️ **MR CRITIQUE — review obligatoire par 2 personnes dont 1 lead
> Cassandra/Apigee.**

## Type de changement

- [ ] MR #1 : Activation multiRegion + ajout DC2 (replication inchangée)
- [ ] MR #2 : Augmentation replication keyspaces `{dc-1:3, dc-2:3}`
- [ ] Autre (décrire) :

## Fichiers modifiés

- [ ] `values/platform/cassandra/values-topology.yaml`
- [ ] `values/platform/cassandra/values-dc2.yaml` (si MR #1)
- [ ] `argo/manifests/04b-cassandra-app-clusterB.yaml` (si MR #1)
- [ ] `argo/manifests/kustomization.yaml` (si nouveau manifeste ajouté)

## Runbook référent

→ `docs/cassandra-phase2.md`

J'ai lu **en entier** le runbook : [ ] oui

## Pré-requis (pour MR #1)

- [ ] Service cross-cluster `cassandra-seed.apigee.internal`
      opérationnel et testé depuis les 2 clusters (`nslookup` + `nc -vz`)
- [ ] cluster-B stack plateforme Apigee en place (AppSets 01-03 synced)
- [ ] Backup Cassandra snapshot fait dans les dernières 24h
- [ ] Fenêtre de maintenance planifiée : date/heure :
- [ ] Au moins 2 opérateurs disponibles pendant la fenêtre

## Pré-requis (pour MR #2)

- [ ] MR #1 mergée et appliquée par ArgoCD
- [ ] Les 3 pods DC2 sont `Running`
- [ ] `nodetool status` montre 6 nodes en `UN`
- [ ] **`nodetool rebuild -- dc-1` exécuté et terminé sur les 3 pods DC2**
      (Load non nul sur chaque pod DC2)
- [ ] Ticket d'exécution avec logs nodetool joint :

## Checklist de vérification du diff

- [ ] Le diff YAML est **exactement** celui prévu par le runbook
      (pas d'autre modification parasite)
- [ ] `multiRegion.enabled` cohérent avec la liste `datacenters`
- [ ] Pas de réduction de `replicaCount` (toute réduction = MR séparée)
- [ ] `keyspacesReplication` ne descend jamais la valeur d'un DC existant
      (uniquement ajouter ou augmenter)

## Review

Obligatoires :

- [ ] Lead Cassandra/Apigee : @___
- [ ] Lead Ops/SRE : @___
- [ ] Équipe plateforme (si impact réseau cross-cluster) : @___

Le merge ne se fait qu'une fois les 3 approbations reçues.

## Plan de sync post-merge

- [ ] Avant merge, freeze du repo Apigee (pas d'autre MR mergée pendant
      la fenêtre)
- [ ] Merge pendant la fenêtre de maintenance
- [ ] Observation active ArgoCD + logs Cassandra pendant les 30 min
      qui suivent
- [ ] Exécution des étapes manuelles nodetool (MR #1 uniquement) —
      tracer chaque commande dans le ticket de run

## Rollback

- MR #1 avant exécution nodetool rebuild : revert + suppression PVCs DC2
- MR #1 après nodetool rebuild (mais avant MR #2) : revert + décommission
  nodes DC2 (`nodetool decommission` sur chaque pod DC2)
- MR #2 mergée : **rollback complexe**, voir runbook §Rollback avec
  le lead Cassandra

---
/label ~apigee ~cassandra ~topology-change ~critical
