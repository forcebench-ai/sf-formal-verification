# One-command checks. Trusted base: docs/trusted-base.md §6.
#
#   make check                   everything CI's Lean job runs
#   make apex-deploy ORG=alias   deploy the subject and run its Apex tests (default alias sfv-dev)
#   make difftest ORG=alias      run the vectors in the org and compare with the Lean interpreter

ORG ?= sfv-dev
SUBJECT ?= subjects/opportunity-stage

DIFFTEST_OUT ?= $(CURDIR)/tools/difftest/out

.PHONY: check build axiomcheck checker-tests lint leanchecker apex-deploy apex-validate apex-test \
	difftest-gen difftest-kernel difftest-self-test difftest

check: build axiomcheck checker-tests lint difftest-self-test difftest-kernel

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
	cd lean && lake env leanchecker SfVerify Spec Proofs Subjects

# Vectors and expected results from the Lean interpreter. Needs no org.
difftest-gen: build
	cd lean && lake exe difftest $(DIFFTEST_OUT)

# The kernel must reproduce every result the compiled interpreter produced. Needs no org.
difftest-kernel: difftest-gen
	cd lean && lake env lean $(DIFFTEST_OUT)/kernel-replay.lean

difftest-self-test:
	python3 tools/difftest/compare.py --self-test
	python3 tools/difftest/run.py --self-test

# Runs anonymous Apex in the reference org (ADR 0003) and compares.
difftest: difftest-gen
	python3 tools/difftest/run.py --dir $(DIFFTEST_OUT) --org $(ORG)

apex-deploy:
	cd $(SUBJECT) && sf project deploy start --source-dir force-app --target-org $(ORG) \
		--test-level RunLocalTests --wait 30

apex-validate:
	cd $(SUBJECT) && sf project deploy validate --source-dir force-app --target-org $(ORG) \
		--test-level RunLocalTests --wait 30

apex-test:
	cd $(SUBJECT) && sf apex run test --target-org $(ORG) --test-level RunLocalTests \
		--code-coverage --result-format human --wait 30
