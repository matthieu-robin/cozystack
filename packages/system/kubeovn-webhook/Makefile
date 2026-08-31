export NAME=kubeovn-webhook
export NAMESPACE=cozy-kubeovn

include ../../../hack/common-envs.mk
include ../../../hack/package.mk

image:
	docker buildx build images/kubeovn-webhook \
		$(call image-tags,kubeovn-webhook,v$(COZYSTACK_VERSION)) \
		$(call cache-args,kubeovn-webhook) \
		--metadata-file images/kubeovn-webhook.json \
		$(BUILDX_ARGS)
	IMAGE="$(REGISTRY)/kubeovn-webhook:$(IMAGE_TAG)@$$(yq e '."containerimage.digest"' images/kubeovn-webhook.json -o json -r)" \
		yq -i '.image = strenv(IMAGE)' values.yaml
	rm -f images/kubeovn-webhook.json

# hack/helm-unit-tests.sh discovers suites by probing `make -n test` per package
# and SKIPS any package that has no such target. This package carried three
# suites under tests/ that consequently never ran in CI -- including the port
# agreement guard, whose whole purpose is to catch a drift that fails open.
# --with-subchart=false matches the other packages: run only our own suites.
test:
	helm unittest --with-subchart=false .
