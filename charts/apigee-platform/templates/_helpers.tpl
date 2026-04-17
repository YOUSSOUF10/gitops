{{/*
Nom du chart
*/}}
{{- define "apigee-platform.name" -}}
apigee-platform
{{- end -}}

{{/*
Labels communs
*/}}
{{- define "apigee-platform.labels" -}}
app.kubernetes.io/name: apigee-platform
app.kubernetes.io/part-of: apigee-hybrid
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Gate de rendu : retourne "true" si la section doit être rendue.
Usage :
  {{- if eq (include "apigee-platform.render" (dict "want" "crds" "only" .Values.render.only)) "true" }}
*/}}
{{- define "apigee-platform.render" -}}
{{- $want := .want -}}
{{- $only := .only | default "all" -}}
{{- if or (eq $only "all") (eq $only $want) -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}
