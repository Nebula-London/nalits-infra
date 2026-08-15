SHELL := /usr/bin/env bash
REGISTRY := registry/tenancies.yaml
PLATFORM := registry/platform.yaml

validate:
	python3 scripts/validate-registry.py validate --file $(REGISTRY) --platform $(PLATFORM)
	bash -n scripts/*.sh
	./scripts/security-check.sh

test: validate
	./tests/registry-test.sh

inventory:
	python3 scripts/generate-inventory.py --registry $(REGISTRY) --out inventory.generated.yaml
