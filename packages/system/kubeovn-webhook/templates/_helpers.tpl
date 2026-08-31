{{- define "namespace-annotation-webhook.name" -}}
kube-ovn-webhook
{{- end }}

{{- define "namespace-annotation-webhook.fullname" -}}
kube-ovn-webhook
{{- end }}

{{/*
The port exposed by the Service. Keep the Service and source-side Cilium policy
on the same value so pod traffic cannot bypass the deny through the ClusterIP.
*/}}
{{- define "namespace-annotation-webhook.servicePort" -}}
443
{{- end }}

{{/*
The port the webhook serves on. Defined once and consumed by the container,
the Service targetPort and the Cilium clusterwide policy, because those three
must agree: the policy has default-deny disabled, so a policy pointed at a port
nothing serves denies nothing while the real port stays open -- a drift that
removes the control silently rather than breaking anything visibly.
*/}}
{{- define "namespace-annotation-webhook.port" -}}
8443
{{- end }}
