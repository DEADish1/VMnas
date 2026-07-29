SHELL := /bin/bash

.PHONY: help iso mac-client server lint clean clean-app-cache

help:
	@echo "VMnas targets:"
	@echo "  make iso     Build the VMnas server installer ISO with Docker"
	@echo "  make mac-client  Build the VMnas Admin macOS app bundle"
	@echo "  make server  Run the development server API locally"
	@echo "  make lint    Run basic syntax checks"
	@echo "  make clean   Remove local build caches and stale app staging files"

iso:
	./server-os/build-iso.sh

mac-client:
	./mac-client/package-app.sh

server:
	cd server-agent && python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements.txt && uvicorn vmnas_agent.main:app --reload --host 127.0.0.1 --port 8765

lint:
	python3 -m py_compile server-agent/vmnas_agent/*.py

clean:
	rm -rf mac-client/.build server-agent/.venv server-agent/vmnas_agent/__pycache__
	find server-agent -name '*.pyc' -delete

clean-app-cache:
	rm -rf "$$HOME/Library/Application Support/VMnas/USBStaging"
