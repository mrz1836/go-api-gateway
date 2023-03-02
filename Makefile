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

## Default S3 bucket (already exists from: infrastructure) to store distribution files
ifndef APPLICATION_BUCKET
	override APPLICATION_BUCKET="mrz-cloudformation-distribution-raw-files"
endif

## Application name (the name of the application, lowercase, no spaces)
ifndef APPLICATION_NAME
	override APPLICATION_NAME="go-api-gateway"
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
	override RELEASES_DIR=./aws-sam
endif

## Application domain name
ifndef APPLICATION_DOMAIN_NAME
	override APPLICATION_DOMAIN_NAME="mrz1818.com"
endif

## VPC name (for identification)
ifndef VPC_NAME
	override VPC_NAME="vpc-main"
endif

## Enable insights (true/false)
ifndef ENABLE_INSIGHTS
	override ENABLE_INSIGHTS="false"
endif

.PHONY: build
build: ## Build the SAM application
	@sam build -t application.yaml --debug

.PHONY: clean
clean: ## Remove previous builds, test cache, and packaged releases
	@go clean -cache -testcache -i -r
	@if [ -d $(DISTRIBUTIONS_DIR) ]; then rm -r $(DISTRIBUTIONS_DIR); fi
	@if [ -d $(RELEASES_DIR) ]; then rm -r $(RELEASES_DIR); fi
	@rm -rf $(TEMPLATE_PACKAGED)

.PHONY: deploy
deploy: ## Build, package and deploy
	@test VPC_NAME
	@test ENABLE_INSIGHTS
	@test APPLICATION_DOMAIN_NAME
	@$(MAKE) build
	@$(MAKE) package
	@SAM_CLI_TELEMETRY=0 sam deploy \
        --s3-bucket "$(APPLICATION_BUCKET)" \
        --stack-name $(APPLICATION_STACK_NAME)  \
        --region $(AWS_REGION) \
        --parameter-overrides ApplicationName=$(APPLICATION_NAME) \
        InsightsEnabled=$(ENABLE_INSIGHTS) \
        ApplicationStackName=$(APPLICATION_STACK_NAME) \
        ApplicationStageName=$(APPLICATION_STAGE_NAME) \
        ApplicationDomain=$(APPLICATION_DOMAIN_NAME) \
        ApplicationBucket=$(APPLICATION_BUCKET) \
        ApplicationBucketPrefix=$(APPLICATION_BUCKET_PREFIX) \
		ApplicationHostedZoneId="$(shell $(MAKE) aws-param-zone \
				domain=$(APPLICATION_DOMAIN_NAME))" \
		ApplicationCertificateId="$(shell $(MAKE) aws-param-certificate \
				domain=$(APPLICATION_DOMAIN_NAME))" \
        ApplicationDockerHubArn="$(shell $(MAKE) aws-param-dockerhub \
                APPLICATION_NAME=$(APPLICATION_NAME) APPLICATION_STAGE_NAME=$(APPLICATION_STAGE_NAME))" \
        ApplicationPrivateSubnet1="$(shell $(MAKE) aws-param-vpc-private-subnet-1 vpc_name=$(VPC_NAME))" \
        ApplicationPrivateSubnet2="$(shell $(MAKE) aws-param-vpc-private-subnet-2 vpc_name=$(VPC_NAME))" \
        VPCId="$(shell $(MAKE) aws-param-vpc-id vpc_name=$(VPC_NAME))" \
        RepoOwner=$(REPO_OWNER) \
        RepoName=$(REPO_NAME) \
        RepoBranch=$(REPO_BRANCH) \
        EncryptionKeyId="$(shell $(MAKE) env-key-location \
				app=$(APPLICATION_NAME) \
				stage=$(APPLICATION_STAGE_NAME))" \
        --capabilities $(IAM_CAPABILITIES) \
        --tags $(AWS_TAGS) \
        --no-fail-on-empty-changeset \
        --no-confirm-changeset

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

.PHONY: save-secrets
save-secrets: ## Helper for saving application secrets to Secrets Manager (extendable for more secrets)
	@# Example: make save-secrets github_token=12345... kms_key_id=b329... stage=<stage>
	@test $(github_token)
	@test $(kms_key_id)
	@test $(example_secret)
	@$(eval example_secret_encrypted := $(shell $(MAKE) encrypt kms_key_id=$(kms_key_id) encrypt_value="$(example_secret)"))
	@$(eval secret_value := $(shell echo '{' \
		'\"github_personal_token\":\"$(github_token)\"' \
		',\"example_secret_encrypted\":\"$(example_secret_encrypted)\"' \
		'}'))
	@$(eval existing_secret := $(shell aws secretsmanager describe-secret --secret-id "$(APPLICATION_STAGE_NAME)/$(APPLICATION_NAME)" --output text))
	@if [ '$(existing_secret)' = "" ]; then\
		echo "Creating a new secret..."; \
		$(MAKE) create-secret \
			name="$(APPLICATION_STAGE_NAME)/$(APPLICATION_NAME)" \
			description="Sensitive credentials for $(APPLICATION_NAME):$(APPLICATION_STAGE_NAME)" \
			secret_value='$(secret_value)' \
			kms_key_id=$(kms_key_id);  \
	else\
		echo "Updating an existing secret..."; \
		$(MAKE) update-secret \
            name="$(APPLICATION_STAGE_NAME)/$(APPLICATION_NAME)" \
        	secret_value='$(secret_value)'; \
	fi

.PHONY: start
start: ## Start the application
	@sam local start-api --debug