#!/usr/bin/make -f

SHELL                   := /usr/bin/env bash
REPO_NAMESPACE          ?= simonfrey
REPO_USERNAME           ?= jamesbrink
REPO_API_URL            ?= https://hub.docker.com/v2
IMAGE_NAME              ?= lobsters
BASE_IMAGE              ?= docker.io/ruby:2.7-alpine
DEVELOPER_BUILD         ?= false
VERSION                 := $(shell git describe --tags --abbrev=0 2>/dev/null || git rev-parse --abbrev-ref HEAD 2>/dev/null)
VCS_REF                 := $(shell git rev-parse --short HEAD 2>/dev/null || echo "0000000")
BUILD_DATE              := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")

# Default target is to build container
.PHONY: default
default: build

# Build the podman image
.PHONY: build
build:
	podman build \
		--build-arg BASE_IMAGE=$(BASE_IMAGE) \
		--build-arg BUILD_DATE=$(BUILD_DATE) \
		--build-arg DEVELOPER_BUILD=$(DEVELOPER_BUILD) \
		--build-arg VCS_REF=$(VCS_REF) \
		--build-arg VERSION=$(VERSION) \
		--tag $(REPO_NAMESPACE)/$(IMAGE_NAME):latest \
		--tag $(REPO_NAMESPACE)/$(IMAGE_NAME):$(VCS_REF) \
		--tag $(REPO_NAMESPACE)/$(IMAGE_NAME):$(VERSION) \
		--file Dockerfile .

# List built images
.PHONY: list
list:
	podman images $(REPO_NAMESPACE)/$(IMAGE_NAME) --filter "dangling=false"

# Run any tests
.PHONY: test
test:
	podman run -t $(REPO_NAMESPACE)/$(IMAGE_NAME) env | grep VERSION | grep $(VERSION)

# Push images to repo
.PHONY: push
push:
	echo "$$REPO_PASSWORD" | podman login -u "$(REPO_USERNAME)" --password-stdin; \
		podman push  $(REPO_NAMESPACE)/$(IMAGE_NAME):latest; \
		podman push  $(REPO_NAMESPACE)/$(IMAGE_NAME):$(VCS_REF); \
		podman push  $(REPO_NAMESPACE)/$(IMAGE_NAME):$(VERSION);

# Update README on registry
.PHONY: push-readme
push-readme:
	echo "Authenticating to $(REPO_API_URL)"; \
		token=$$(curl -s -X POST -H "Content-Type: application/json" -d '{"username": "$(REPO_USERNAME)", "password": "'"$$REPO_PASSWORD"'"}' $(REPO_API_URL)/users/login/ | jq -r .token); \
		code=$$(jq -n --arg description "$$(<README.md)" '{"registry":"registry-1.docker.io","full_description": $$description }' | curl -s -o /dev/null  -L -w "%{http_code}" $(REPO_API_URL)/repositories/$(REPO_NAMESPACE)/$(IMAGE_NAME)/ -d @- -X PATCH -H "Content-Type: application/json" -H "Authorization: JWT $$token"); \
		if [ "$$code" != "200" ]; \
		then \
			echo "Failed to update README.md"; \
			exit 1; \
		else \
			echo "Success"; \
		fi;

# Trigger update of micro-badge
.PHONY: update-micro-badge
update-micro-badge:
	curl -d 'update' "https://hooks.microbadger.com/images/$(REPO_NAMESPACE)/$(IMAGE_NAME)/$$MICROBADGER_TOKEN"

# Remove existing images
.PHONY: clean
clean:
	podman rmi $$(podman images $(REPO_NAMESPACE)/$(IMAGE_NAME) --format="{{.Repository}}:{{.Tag}}") --force
