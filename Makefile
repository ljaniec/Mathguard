.PHONY: setup run credentials doctor test smoke fast
export MODEL

# MODEL is optional when the local service has exactly one installed model.
setup:
	python3 scripts/judge.py setup
run:
	bash scripts/demo.sh
credentials:
	python3 scripts/judge.py credentials
doctor:
	python3 scripts/judge.py doctor
test:
	bash scripts/check-local.sh
smoke:
	python3 scripts/smoke-startup.py
fast:
	bash scripts/check-fast.sh
