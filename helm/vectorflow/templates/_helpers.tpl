{{/*
Expand the name of the chart.
*/}}
{{- define "vectorflow.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "vectorflow.fullname" -}}
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
{{- define "vectorflow.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "vectorflow.labels" -}}
helm.sh/chart: {{ include "vectorflow.chart" . }}
{{ include "vectorflow.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.global.labels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "vectorflow.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vectorflow.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "vectorflow.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "vectorflow.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Gateway full name
*/}}
{{- define "vectorflow.gateway.fullname" -}}
{{- printf "%s-gateway" (include "vectorflow.fullname" .) }}
{{- end }}

{{/*
Worker full name
*/}}
{{- define "vectorflow.worker.fullname" -}}
{{- printf "%s-worker" (include "vectorflow.fullname" .) }}
{{- end }}

{{/*
Inference full name
*/}}
{{- define "vectorflow.inference.fullname" -}}
{{- printf "%s-inference" (include "vectorflow.fullname" .) }}
{{- end }}

{{/*
Frontend full name
*/}}
{{- define "vectorflow.frontend.fullname" -}}
{{- printf "%s-frontend" (include "vectorflow.fullname" .) }}
{{- end }}
