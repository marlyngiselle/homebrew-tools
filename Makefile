# Developer entry points. CI calls the same scripts.

VERSION ?= 0.1.0

.PHONY: help test lint audit tarball clean

help: ## List the targets
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{ printf "  %-8s %s\n", $$1, $$2 }'

test: ## Run every bats suite (tools and release scripts)
	bats tools/*/test tests

lint: ## ShellCheck the scripts, ruby -c the formulae, actionlint the workflows
	shellcheck --severity=style $$(find tools scripts -type f \( -perm -u+x -o -name '*.sh' \) | sort)
	for f in Formula/*.rb; do ruby -c $$f >/dev/null || exit 1; done
	actionlint

audit: ## Everything above plus brew style and, if tapped, brew audit
	scripts/local-audit.sh

tarball: ## Build dist/homebrew-tools-$(VERSION).tar.gz reproducibly
	scripts/build-tarball.sh $(VERSION) dist

clean: ## Remove build output
	rm -rf dist
