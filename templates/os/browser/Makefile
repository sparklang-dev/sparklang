# browser_mitm scaffold — owner hooks only
# Live run targets live in ../spark-browser/Makefile.
# Never install CA or reboot from automation.

.PHONY: help scaffold product-run product-test analyze

SPARK_ROOT := $(abspath ../..)
BROWSER ?= $(abspath $(SPARK_ROOT)/../spark-browser)

help:
	@echo "browser_mitm scaffold (out/os/browser_mitm)"
	@echo "  make scaffold      # refresh blueprint via spark tools"
	@echo "  make product-run   # cd spark-browser && make run"
	@echo "  make product-test  # cd spark-browser && make test"
	@echo "  make analyze HAR=… # spark-browser mitm analyze"

scaffold:
	$(MAKE) -C $(SPARK_ROOT) browser-scaffold

product-run:
	$(MAKE) -C $(BROWSER) run

product-test:
	$(MAKE) -C $(BROWSER) test

analyze:
	@test -n "$(HAR)" || (echo "usage: make analyze HAR=…"; exit 2)
	$(MAKE) -C $(BROWSER) analyze HAR="$(HAR)"
