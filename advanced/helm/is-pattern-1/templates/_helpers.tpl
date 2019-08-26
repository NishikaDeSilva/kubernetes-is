{{- define "db_connect_url" -}}
  {{- if .Values.wso2.connector.mysql.enabled -}}
    {{- printf "jdbc:mysql://%s:%s/CONN_DB_NAME?autoReconnect=true&amp;useSSL=false" .Values.wso2.connector.host .Values.wso2.connector.port -}}
  {{- else if .Values.wso2.connector.postgres.enabled -}}
    {{- printf "jdbc:postgresql://%s:%s/CONN_DB_NAME" .Values.wso2.connector.host .Values.wso2.connector.port -}}
  {{- end -}}
{{- end -}}
