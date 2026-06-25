# Makefile for lab_05 — VXLAN EVPN overlay lab
# All commands run without sudo (user must be in docker/clab_admins groups)

NETLAB_DIR := netlab
TEST_DIR   := tests
OUTPUT_DIR := $(TEST_DIR)/output

.PHONY: up down restart test test-verbose clean status connect

## Start the lab (containers + config push)
up:
	cd $(NETLAB_DIR) && netlab up --no-config

## Stop the lab and remove containers
down:
	cd $(NETLAB_DIR) && netlab down

## Restart the lab (down then up)
restart: down up

## Show lab status
status:
	cd $(NETLAB_DIR) && netlab status

## Connect to a node (usage: make connect NODE=spine1)
connect:
	cd $(NETLAB_DIR) && netlab connect $(NODE)

## Run all Robot Framework tests
test: $(OUTPUT_DIR)
	cd $(TEST_DIR) && PYTHONPATH=. PROJECT_DIR=.. robot --outputdir output test_evpn_vxlan.robot

## Run tests with verbose log level
test-verbose: $(OUTPUT_DIR)
	cd $(TEST_DIR) && PYTHONPATH=. PROJECT_DIR=.. robot --outputdir output --loglevel DEBUG test_evpn_vxlan.robot

## Run a single test by name (usage: make test-one TEST="Host1 Should Ping Host2 Through Overlay")
test-one: $(OUTPUT_DIR)
	cd $(TEST_DIR) && PYTHONPATH=. PROJECT_DIR=.. robot --outputdir output --test "$(TEST)" test_evpn_vxlan.robot

## Create output directory
$(OUTPUT_DIR):
	mkdir -p $(OUTPUT_DIR)

## Clean test outputs
clean:
	rm -rf $(OUTPUT_DIR)

## Show help
help:
	@echo "lab_05 — VXLAN EVPN overlay lab"
	@echo ""
	@echo "Targets:"
	@echo "  up            Start the lab"
	@echo "  down          Stop the lab"
	@echo "  restart       Restart the lab"
	@echo "  status        Show lab status"
	@echo "  connect NODE  Connect to a node (e.g. make connect NODE=spine1)"
	@echo "  test          Run all Robot Framework tests"
	@echo "  test-verbose  Run tests with DEBUG log level"
	@echo '  test-one TEST Run a single test (e.g. make test-one TEST="Host1 Should Ping Host2")'
	@echo "  clean         Remove test outputs"
	@echo "  help          Show this help"
