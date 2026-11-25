# machine-report build targets.
# Needs bash, shellcheck, and bats (Ubuntu packages: shellcheck, bats).

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

.PHONY: check lint test

SCRIPTS := install.sh linux.sh spark.sh wsl.sh

lint:
	shellcheck $(SCRIPTS)

test:
	bats tests

check: lint test
