{{/*
Common labels for all resources
*/}}
{{- define "lab-gitea.labels" -}}
app.kubernetes.io/part-of: {{ .Chart.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Gitea selector labels
*/}}
{{- define "lab-gitea.gitea.selectorLabels" -}}
app.kubernetes.io/name: {{ .Values.gitea.name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: {{ .Values.gitea.name }}
{{- end }}

{{/*
PostgreSQL selector labels
*/}}
{{- define "lab-gitea.postgres.selectorLabels" -}}
app.kubernetes.io/name: {{ .Values.postgres.name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: {{ .Values.postgres.name }}
{{- end }}

{{/*
Database host:port helper
*/}}
{{- define "lab-gitea.dbHost" -}}
{{- if .Values.postgres.enabled -}}
{{ .Values.postgres.name }}:{{ .Values.postgres.port }}
{{- else -}}
{{ .Values.externalPostgres.host }}:{{ .Values.externalPostgres.port }}
{{- end -}}
{{- end }}

{{- define "lab-gitea.dbHostOnly" -}}
{{- if .Values.postgres.enabled -}}
{{ .Values.postgres.name }}
{{- else -}}
{{ .Values.externalPostgres.host }}
{{- end -}}
{{- end }}

{{- define "lab-gitea.dbPort" -}}
{{- if .Values.postgres.enabled -}}
{{ .Values.postgres.port }}
{{- else -}}
{{ .Values.externalPostgres.port }}
{{- end -}}
{{- end }}

{{- define "lab-gitea.dbName" -}}
{{- if .Values.postgres.enabled -}}
{{ .Values.postgres.db }}
{{- else -}}
{{ .Values.externalPostgres.db }}
{{- end -}}
{{- end }}

{{- define "lab-gitea.dbUser" -}}
{{- if .Values.postgres.enabled -}}
{{ .Values.postgres.user }}
{{- else -}}
{{ .Values.externalPostgres.user }}
{{- end -}}
{{- end }}

{{/*
Shared Gitea environment variables (used by both initContainer and main container)
*/}}
{{- define "lab-gitea.gitea.env" -}}
- name: GITEA_WORK_DIR
  value: "/var/lib/gitea"
- name: GITEA_APP_INI
  value: "/etc/gitea/app.ini"
- name: GITEA__DEFAULT__APP_NAME
  value: {{ .Values.gitea.config.appName | quote }}
- name: GITEA__server__DOMAIN
  value: {{ .Values.gitea.domain | quote }}
- name: GITEA__server__ROOT_URL
  value: {{ .Values.gitea.rootUrl | quote }}
- name: GITEA__server__HTTP_PORT
  value: {{ .Values.gitea.httpPort | quote }}
- name: GITEA__server__DISABLE_SSH
  value: {{ not .Values.gitea.ssh.enabled | quote }}
{{- if .Values.gitea.ssh.enabled }}
- name: GITEA__server__START_SSH_SERVER
  value: "true"
- name: GITEA__server__SSH_LISTEN_PORT
  value: {{ .Values.gitea.ssh.port | quote }}
- name: GITEA__server__SSH_PORT
  value: {{ .Values.gitea.ssh.servicePort | quote }}
{{- end }}
- name: GITEA__database__DB_TYPE
  value: "postgres"
- name: GITEA__database__HOST
  value: {{ include "lab-gitea.dbHost" . | quote }}
- name: GITEA__database__NAME
  value: {{ include "lab-gitea.dbName" . | quote }}
- name: GITEA__database__USER
  value: {{ include "lab-gitea.dbUser" . | quote }}
{{- if not .Values.postgres.enabled }}
- name: GITEA__database__SSL_MODE
  value: {{ .Values.externalPostgres.sslMode | quote }}
{{- else }}
- name: GITEA__database__SSL_MODE
  value: "disable"
{{- end }}
- name: GITEA__database__PASSWD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.existingSecret | quote }}
      key: {{ .Values.secretKeys.dbPassword | quote }}
- name: GITEA__security__INSTALL_LOCK
  value: "true"
- name: GITEA__security__SECRET_KEY
  valueFrom:
    secretKeyRef:
      name: {{ .Values.existingSecret | quote }}
      key: {{ .Values.secretKeys.secretKey | quote }}
- name: GITEA__security__INTERNAL_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ .Values.existingSecret | quote }}
      key: {{ .Values.secretKeys.internalToken | quote }}
- name: GITEA__oauth2__JWT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ .Values.existingSecret | quote }}
      key: {{ .Values.secretKeys.jwtSecret | quote }}
- name: GITEA__service__DISABLE_REGISTRATION
  value: {{ .Values.gitea.config.disableRegistration | quote }}
- name: GITEA__service__ALLOW_ONLY_EXTERNAL_REGISTRATION
  value: {{ .Values.gitea.config.allowOnlyExternalRegistration | quote }}
- name: GITEA__service__SHOW_REGISTRATION_BUTTON
  value: {{ .Values.gitea.config.showRegistrationButton | quote }}
- name: GITEA__openid__ENABLE_OPENID_SIGNIN
  value: {{ .Values.gitea.config.enableOpenidSignin | quote }}
- name: GITEA__openid__ENABLE_OPENID_SIGNUP
  value: {{ .Values.gitea.config.enableOpenidSignup | quote }}
- name: GITEA__oauth2_client__ENABLE_AUTO_REGISTRATION
  value: {{ .Values.gitea.config.oauth2EnableAutoRegistration | quote }}
- name: GITEA__oauth2_client__ACCOUNT_LINKING
  value: {{ .Values.gitea.config.oauth2AccountLinking | quote }}
- name: GITEA__oauth2_client__UPDATE_AVATAR
  value: {{ .Values.gitea.config.oauth2UpdateAvatar | quote }}
- name: GITEA__ui__DEFAULT_THEME
  value: {{ .Values.gitea.config.defaultTheme | quote }}
- name: GITEA__log__LEVEL
  value: {{ .Values.gitea.config.logLevel | quote }}
{{- with .Values.gitea.config.extraEnv }}
{{ toYaml . }}
{{- end }}
{{- end }}
