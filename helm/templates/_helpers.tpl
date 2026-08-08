{{- define "crafty.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "crafty.fullname" -}}
{{- printf "%s" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "crafty.labels" -}}
app.kubernetes.io/name: {{ include "crafty.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "crafty.selectorLabels" -}}
app.kubernetes.io/name: {{ include "crafty.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "crafty.pvcName" -}}
{{- if .Values.persistence.existingClaim -}}
{{ .Values.persistence.existingClaim }}
{{- else -}}
{{ include "crafty.fullname" . }}-data
{{- end -}}
{{- end -}}

{{- define "crafty.backupsPvcName" -}}
{{- if .Values.persistence.backups.existingClaim -}}
{{ .Values.persistence.backups.existingClaim }}
{{- else -}}
{{ include "crafty.fullname" . }}-backups
{{- end -}}
{{- end -}}
