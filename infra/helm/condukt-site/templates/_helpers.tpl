{{- define "condukt-site.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "condukt-site.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "condukt-site.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "condukt-site.labels" -}}
app.kubernetes.io/name: {{ include "condukt-site.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}

{{- define "condukt-site.selectorLabels" -}}
app.kubernetes.io/name: {{ include "condukt-site.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "condukt-site.webLabels" -}}
{{ include "condukt-site.labels" . }}
app.kubernetes.io/component: web
{{- end -}}

{{- define "condukt-site.webSelectorLabels" -}}
{{ include "condukt-site.selectorLabels" . }}
app.kubernetes.io/component: web
{{- end -}}

{{- define "condukt-site.appSecretName" -}}
{{ include "condukt-site.fullname" . }}-app
{{- end -}}

{{- define "condukt-site.postgresClusterName" -}}
{{ include "condukt-site.fullname" . }}-postgres
{{- end -}}

{{- define "condukt-site.postgresAppSecret" -}}
{{ include "condukt-site.postgresClusterName" . }}-app
{{- end -}}
