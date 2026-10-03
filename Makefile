.PHONY: run test fast
run:
	bash scripts/demo.sh
test:
	bash scripts/check-local.sh
fast:
	bash scripts/check-fast.sh
