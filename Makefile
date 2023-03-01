## Set the binary name
CUSTOM_BINARY_NAME := main

# Common makefile commands & variables between projects
include .make/common.mk

# Common Golang makefile commands & variables between projects
include .make/go.mk

# Common aws commands & variables between projects
include .make/aws.mk

## Stage or environment for the application
ifndef APPLICATION_STAGE_NAME
	override APPLICATION_STAGE_NAME="production"
endif

## Default S3 bucket (already exists) to store distribution files
ifndef APPLICATION_BUCKET
	override APPLICATION_BUCKET="mrz-cloudformation-distribution-raw-files"
endif

## Application name (the name of the application, lowercase, no spaces)
ifndef APPLICATION_NAME
	override APPLICATION_NAME="main"
endif

## Tags for the application in AWS
ifndef AWS_TAGS
	override AWS_TAGS="Stage=$(APPLICATION_STAGE_NAME) Product=$(APPLICATION_NAME)"
endif

## Cloud formation stack name (combines the app name with the stage for unique stacks)
ifndef APPLICATION_STACK_NAME
	override APPLICATION_STACK_NAME=$(subst _,-,"$(APPLICATION_NAME)-$(APPLICATION_STAGE_NAME)")
endif

## Application feature name (if it's a feature branch of a stage) (feature="some-feature")
ifdef APPLICATION_FEATURE_NAME
	override APPLICATION_STACK_NAME=$(subst _,-,"$(APPLICATION_NAME)-$(APPLICATION_STAGE_NAME)-$(APPLICATION_FEATURE_NAME)")
endif

## S3 prefix to store the distribution files
ifndef APPLICATION_BUCKET_PREFIX
	override APPLICATION_BUCKET_PREFIX=$(APPLICATION_STACK_NAME)
endif

## Not defined? Use default repo name which is the application
ifeq ($(REPO_NAME),)
	REPO_NAME="go-api-gateway"
endif

## Not defined? Use default repo owner
ifeq ($(REPO_OWNER),)
	REPO_OWNER="mrz1836"
endif

## Default branch for webhooks
ifndef REPO_BRANCH
	override REPO_BRANCH="master"
endif

## Set the release folder
ifndef RELEASES_DIR
	override RELEASES_DIR=./releases
endif

## Package directory name
ifndef PACKAGE_NAME
	override PACKAGE_NAME=$(BINARY_NAME)
endif

## Set the local environment variables when using "run"
ifndef LOCAL_ENV_FILE
	override LOCAL_ENV_FILE=local-env.json
endif

## Set the Lambda Security Group
ifndef APPLICATION_SECURITY_GROUP
	override APPLICATION_SECURITY_GROUP="sg-0cb3239ebcff52f86"
endif

## Set the Lambda Subnet 1 for the VPC
ifndef APPLICATION_PRIVATE_SUBNET_1
	override APPLICATION_PRIVATE_SUBNET_1="subnet-05d8fcf25b7bb4694"
endif

start: ## Start the application
	@sam local start-api -t application.yaml --debug

build-sam: ## Build the SAM application
	@sam build -t application.yaml --debug

# GOARCH=amd64 GOOS=linux go build main.go -ldflags="-s -w"

#build: ## Build the lambda function as a compiled application
#		@for dir in `ls cmd/functions`; do \
#			GOOS=linux go build -o dist/handler/$$dir github.com/$(REPO_OWNER)/go-api-gateway/cmd/functions/$$dir; \
#		done

.PHONY: build
build: ## Build the lambda function as a compiled application
	@go build -o $(RELEASES_DIR)/$(PACKAGE_NAME)/$(BINARY_NAME) .

.PHONY: clean
clean: ## Remove previous builds, test cache, and packaged releases
	@go clean -cache -testcache -i -r
	@if [ -d $(DISTRIBUTIONS_DIR) ]; then rm -r $(DISTRIBUTIONS_DIR); fi
	@if [ -d $(RELEASES_DIR) ]; then rm -r $(RELEASES_DIR); fi
	@rm -rf $(TEMPLATE_PACKAGED)

.PHONY: deploy
deploy: ## Build, prepare and deploy
	@$(MAKE) lambda
	@$(MAKE) package
	@SAM_CLI_TELEMETRY=0 sam deploy \
        --template-file $(TEMPLATE_PACKAGED) \
        --stack-name $(APPLICATION_STACK_NAME)  \
        --region $(AWS_REGION) \
        --parameter-overrides ApplicationName=$(APPLICATION_NAME) \
        ApplicationStackName=$(APPLICATION_STACK_NAME) \
        ApplicationStageName=$(APPLICATION_STAGE_NAME) \
        ApplicationBucket=$(APPLICATION_BUCKET) \
        ApplicationBucketPrefix=$(APPLICATION_BUCKET_PREFIX) \
        ApplicationDockerHubArn="$(shell $(MAKE) aws-param-dockerhub \
                APPLICATION_NAME=$(APPLICATION_NAME) APPLICATION_STAGE_NAME=$(APPLICATION_STAGE_NAME))" \
        RepoOwner=$(REPO_OWNER) \
        RepoName=$(REPO_NAME) \
        RepoBranch=$(REPO_BRANCH) \
        ApplicationSecurityGroup=$(APPLICATION_SECURITY_GROUP) \
        ApplicationPrivateSubnet1=$(APPLICATION_PRIVATE_SUBNET_1) \
        EncryptionKeyId="$(shell $(MAKE) env-key-location \
				app=$(APPLICATION_NAME) \
				stage=$(APPLICATION_STAGE_NAME))" \
        --capabilities $(IAM_CAPABILITIES) \
        --tags $(AWS_TAGS) \
        --no-fail-on-empty-changeset \
        --no-confirm-changeset

.PHONY: lambda
lambda: ## Build a compiled version to deploy to Lambda
	@$(MAKE) test
	GOOS=linux GOARCH=amd64 CGO_ENABLED=0 $(MAKE) build

.PHONY: run
run: ## Fires the lambda function (run event=hello_world)
	@$(MAKE) lambda
	@if [ "$(event)" = "" ]; then echo $(eval event += hello_world); fi
	@SAM_CLI_TELEMETRY=0 sam local invoke ShieldFunction \
		--force-image-build \
		-e events/$(event).json \
		--template $(TEMPLATE_RAW) \
		--env-vars $(LOCAL_ENV_FILE)

.PHONY: save-dockerhub-credentials
save-dockerhub-credentials: ## Helper for saving DockerHub credentials to Secrets Manager
	@# Example: make save-dockerhub-credentials stage=production username=test123 password=test123
	@$(info Testing variables...)
	@[ "${username}" ] || ( echo ">> username is not set"; exit 1 )
	@[ "${password}" ] || ( echo ">> password is not set"; exit 1 )
	@[ "${kms_key_id}" ] || ( echo ">> kms_key_id is not set"; exit 1 )
	@$(eval secret_value := $(shell echo '{' \
		'\"username\":\"$(username)\"' \
		',\"password\":\"$(password)\"' \
		'}'))

	@$(info Getting existing credentials...)
	@$(eval existing_secret := $(shell aws secretsmanager describe-secret --secret-id "$(APPLICATION_STAGE_NAME)/$(APPLICATION_NAME)/dockerhub" --output text))
	@$(info Starting save process...)
	@if [ '$(existing_secret)' = "" ]; then\
		echo "Creating a new DockerHub credential..."; \
		$(MAKE) create-secret \
			name="$(APPLICATION_STAGE_NAME)/$(APPLICATION_NAME)/dockerhub" \
			description="Sensitive credentials for $(APPLICATION_STAGE_NAME):$(APPLICATION_NAME):dockerhub" \
			secret_value='$(secret_value)' \
			kms_key_id=$(kms_key_id);  \
	else\
		echo "Updating existing DockerHub credentials..."; \
		$(MAKE) update-secret \
            name="$(APPLICATION_STAGE_NAME)/$(APPLICATION_NAME)/dockerhub" \
        	secret_value='$(secret_value)'; \
	fi

.PHONY: save-dockerhub-arn
save-dockerhub-arn: ## Updates the ARN for the DockerHub secret
	@$(info Testing variables...)
	@test $(arn)
	@$(info Saving DockerHub parameter...)
	@$(MAKE) save-param param_name="/$(APPLICATION_STAGE_NAME)/$(APPLICATION_NAME)/dockerhub" param_value=$(arn)