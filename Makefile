# One-command checks. Trusted base: docs/trusted-base.md §6.
#
#   make check                   everything CI's Lean job runs
#   make apex-deploy ORG=alias   deploy the subject and run its Apex tests (default alias afv-dev)

ORG ?= afv-dev
SUBJECT ?= subjects/opportunity-stage

.PHONY: check build axiomcheck checker-tests lint leanchecker apex-deploy apex-validate apex-test

check: build axiomcheck checker-tests lint

build:
	cd lean && lake build

axiomcheck: build
	cd lean && lake exe axiomcheck

checker-tests: build
	cd lean && ./test/axiomcheck/run.sh

lint:
	python3 tools/lint/escape_hatches.py --self-test
	python3 tools/lint/escape_hatches.py

# Upstream kernel replay, as a second opinion next to axiomcheck's own replay.
leanchecker: build
	cd lean && lake env leanchecker ApexVerify Spec Proofs Subjects

apex-deploy:
	cd $(SUBJECT) && sf project deploy start --source-dir force-app --target-org $(ORG) \
		--test-level RunLocalTests --wait 30

apex-validate:
	cd $(SUBJECT) && sf project deploy validate --source-dir force-app --target-org $(ORG) \
		--test-level RunLocalTests --wait 30

apex-test:
	cd $(SUBJECT) && sf apex run test --target-org $(ORG) --test-level RunLocalTests \
		--code-coverage --result-format human --wait 30
