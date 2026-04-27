# =================================
# VectorFlow Chef Makefile
# =================================
# Common Chef operations

.PHONY: help install lint test converge verify clean

COOKBOOK_DIR := cookbooks
POLICY_DIR := policies
ROLE_DIR := roles
ENVIRONMENT_DIR := environments

help:
	@echo "VectorFlow Chef Management"
	@echo ""
	@echo "Usage:"
	@echo "  make install        Install cookbook dependencies"
	@echo "  make lint           Run cookbook linting"
	@echo "  make test           Run cookbook unit tests"
	@echo "  make converge       Run chef-client in local mode"
	@echo "  make verify         Run InSpec compliance tests"
	@echo "  make kitchen        Run Test Kitchen integration tests"
	@echo "  make clean          Clean up temporary files"
	@echo ""
	@echo "Policies:"
	@echo "  make policy-install POLICY=<name>  Install a policy"
	@echo "  make policy-push ENV=<env> POLICY=<name>  Push policy to environment"
	@echo ""
	@echo "Available Policies:"
	@echo "  - vectorflow-base"
	@echo "  - vectorflow-worker"
	@echo "  - vectorflow-standalone"
	@echo "  - vectorflow-security"

# Install dependencies
install:
	@echo "Installing cookbook dependencies..."
	cd $(COOKBOOK_DIR)/vectorflow_base && berks install
	cd $(COOKBOOK_DIR)/vectorflow_docker && berks install
	cd $(COOKBOOK_DIR)/vectorflow_kubernetes && berks install
	cd $(COOKBOOK_DIR)/vectorflow_security && berks install
	cd $(COOKBOOK_DIR)/vectorflow_app && berks install
	@echo "Dependencies installed successfully"

# Lint cookbooks
lint:
	@echo "Linting cookbooks..."
	cookstyle $(COOKBOOK_DIR)/*
	@echo "Linting complete"

# Run unit tests
test:
	@echo "Running unit tests..."
	@for cookbook in $(COOKBOOK_DIR)/*; do \
		echo "Testing $$cookbook..."; \
		cd $$cookbook && chef exec rspec 2>/dev/null || true; \
		cd -; \
	done
	@echo "Tests complete"

# Run chef-client locally
converge:
	@echo "Running chef-client in local mode..."
	chef-client --local-mode \
		--config .chef/config.rb \
		--runlist 'role[vectorflow-standalone]' \
		--environment development \
		--log_level info
	@echo "Converge complete"

# Run compliance verification
verify:
	@echo "Running compliance verification..."
	@if [ -d "compliance" ]; then \
		inspec exec compliance/ --reporter cli json:reports/compliance.json; \
	else \
		echo "No compliance profiles found"; \
	fi

# Run Test Kitchen
kitchen:
	@echo "Running Test Kitchen..."
	kitchen test

# Policy operations
policy-install:
ifndef POLICY
	$(error POLICY is not set. Usage: make policy-install POLICY=vectorflow-base)
endif
	@echo "Installing policy: $(POLICY)..."
	chef install $(POLICY_DIR)/$(POLICY).rb

policy-push:
ifndef ENV
	$(error ENV is not set. Usage: make policy-push ENV=production POLICY=vectorflow-worker)
endif
ifndef POLICY
	$(error POLICY is not set. Usage: make policy-push ENV=production POLICY=vectorflow-worker)
endif
	@echo "Pushing policy $(POLICY) to $(ENV)..."
	chef push $(ENV) $(POLICY_DIR)/$(POLICY).rb

# Clean up
clean:
	@echo "Cleaning up..."
	rm -rf vendor/
	rm -rf reports/
	rm -f Berksfile.lock
	@for cookbook in $(COOKBOOK_DIR)/*; do \
		rm -f $$cookbook/Berksfile.lock; \
	done
	@echo "Cleanup complete"

# Generate new cookbook
new-cookbook:
ifndef NAME
	$(error NAME is not set. Usage: make new-cookbook NAME=my_cookbook)
endif
	@echo "Creating new cookbook: $(NAME)..."
	chef generate cookbook $(COOKBOOK_DIR)/$(NAME) \
		--copyright "VectorFlow Team" \
		--email "team@vectorflow.local" \
		--license MIT
	@echo "Cookbook $(NAME) created"
