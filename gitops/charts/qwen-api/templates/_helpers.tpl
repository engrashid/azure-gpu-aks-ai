{{/*
Expand the name of the chart.
*/}}
{{- define "qwen-api.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
Truncated to 63 chars (Kubernetes DNS label limit).
If the release name already contains the chart name, use it directly.
*/}}
{{- define "qwen-api.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "qwen-api.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels — applied to every resource in this chart.
*/}}
{{- define "qwen-api.labels" -}}
helm.sh/chart: {{ include "qwen-api.chart" . }}
{{ include "qwen-api.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: workloads
{{- end }}

{{/*
Selector labels — used in matchLabels and pod template labels.
These must be stable; changing them forces a rolling replacement.
*/}}
{{- define "qwen-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "qwen-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
PV name — cluster-scoped, must be globally unique.
Encodes release name to support multiple installs on the same cluster.
*/}}
{{- define "qwen-api.pvName" -}}
{{- printf "%s-models-pv" (include "qwen-api.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
PVC name.
*/}}
{{- define "qwen-api.pvcName" -}}
{{- printf "%s-models" (include "qwen-api.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
ConfigMap name.
*/}}
{{- define "qwen-api.configMapName" -}}
{{- printf "%s-config" (include "qwen-api.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
