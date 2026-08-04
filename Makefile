SHELL := /bin/bash

.PHONY: help iso mac-client server lint clean clean-app-cache

help:
	@echo "Camo NAS targets:"
	@echo "  make iso     Build the Camo NAS server installer ISO with Docker"
	@echo "  make mac-client  Build the Camo NAS Admin macOS app bundle"
	@echo "  make server  Run the development server API locally"
	@echo "  make lint    Run basic syntax checks"
	@echo "  make clean   Remove local build caches and stale app staging files"

iso:
	./server-os/build-iso.sh

mac-client:
	./mac-client/package-app.sh

server:
	cd server-agent && python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements.txt && uvicorn camonas_agent.main:app --reload --host 127.0.0.1 --port 8765

lint:
	python3 -m py_compile server-agent/camonas_agent/*.py

clean:
	rm -rf mac-client/.build mac-client/.build-stale-* server-agent/.venv server-agent/camonas_agent/__pycache__ windows-client/bin windows-client/obj
	rm -rf "dist/mac-client/Camo NAS Admin-stale-"*.app "mac-client 2" "server-os 2"
	rm -f .DS_Store usb-write-*.log dist/mac-client/build.log
	find server-agent -name '*.pyc' -delete

clean-app-cache:
	rm -rf "$$HOME/Library/Application Support/CamoNAS/USBStaging"
