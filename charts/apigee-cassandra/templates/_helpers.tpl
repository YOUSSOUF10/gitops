{{/*
Nom de release standardisé.
*/}}
{{- define "apigee-cassandra.name" -}}
apigee-cassandra
{{- end -}}

{{/*
Labels communs à toutes les ressources Cassandra.
*/}}
{{- define "apigee-cassandra.labels" -}}
app.kubernetes.io/name: apigee-cassandra
app.kubernetes.io/part-of: apigee-hybrid
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Détermine si on est en mode multi-DC.
*/}}
{{- define "apigee-cassandra.isMultiDC" -}}
{{- if and .Values.cassandra.multiRegion.enabled (gt (len .Values.cassandra.datacenters) 1) -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}
