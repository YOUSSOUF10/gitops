{{/*
========================================================================
Helpers apigee-tenant
========================================================================
Centralise la logique conditionnelle (type, render, mode) pour éviter
de la répéter dans chaque template.
*/}}

{{/*
Labels communs — incluent le tenant, le cluster, l'appUID
*/}}
{{- define "apigee-tenant.labels" -}}
app.kubernetes.io/name: apigee-tenant
app.kubernetes.io/part-of: apigee-hybrid
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
apigee.cloud.google.com/tenant: {{ .Values.tenant.name | quote }}
apigee.cloud.google.com/cluster: {{ .Values.tenant.cluster | quote }}
appUID: {{ .Values.tenant.appUID | quote }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Nom court du tenant, safe pour Kubernetes (pas de préfixe _)
Ex. "_infra-nonprod" → "infra-nonprod"
*/}}
{{- define "apigee-tenant.safeName" -}}
{{- .Values.tenant.name | trimPrefix "_" -}}
{{- end -}}

{{/*
Gate de rendu : true si la section demandée doit être rendue.
Usage :
  {{- if eq (include "apigee-tenant.render" (dict "want" "exposure" "root" .)) "true" }}
*/}}
{{- define "apigee-tenant.render" -}}
{{- $want := .want -}}
{{- $only := .root.Values.render.only | default "all" -}}
{{- if or (eq $only "all") (eq $only $want) -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}

{{/*
Tenant technique (type: infra) : ne pose PAS d'ApigeeEnvironment,
ni d'ExternalSecrets SA GCP applicatifs.
*/}}
{{- define "apigee-tenant.isInfra" -}}
{{- if eq (.Values.tenant.type | default "standard") "infra" -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}

{{/*
IngressGateway en mode dedicated : le tenant POSE la gateway.
En mode shared : le tenant NE POSE RIEN (il référence seulement).
*/}}
{{- define "apigee-tenant.isDedicatedGateway" -}}
{{- if eq .Values.ingressGateway.mode "dedicated" -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}

{{/*
Nom effectif de la gateway à référencer dans l'EnvGroup (shared ou dedicated).
*/}}
{{- define "apigee-tenant.gatewayName" -}}
{{- if eq .Values.ingressGateway.mode "dedicated" -}}
{{ .Values.ingressGateway.name }}
{{- else -}}
{{ .Values.ingressGateway.sharedGatewayName }}
{{- end -}}
{{- end -}}

{{/*
Chemin Vault complet pour une clé donnée.
Usage: include "apigee-tenant.vaultPath" (dict "root" . "key" "sa-synchronizer.json")
*/}}
{{- define "apigee-tenant.vaultPath" -}}
{{ .root.Values.vault.mountPath }}/{{ .key }}
{{- end -}}
