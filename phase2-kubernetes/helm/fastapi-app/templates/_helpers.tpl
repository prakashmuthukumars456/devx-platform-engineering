{{/*
_helpers.tpl — reusable named templates
Call these with: {{ include "fastapi-app.fullname" . }}
*/}}

{{/* Full name: release-name + chart-name */}}
{{- define "fastapi-app.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Common labels added to every resource */}}
{{- define "fastapi-app.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
