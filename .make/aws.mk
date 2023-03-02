## Default region for the application
ifndef AWS_REGION
	ifdef AWS_DEFAULT_REGION
		override AWS_REGION=AWS_DEFAULT_REGION
	else
		override AWS_REGION=us-east-1
	endif
endif
export AWS_REGION

## Set capabilities for the sam deploy option
ifndef IAM_CAPABILITIES
	override IAM_CAPABILITIES="CAPABILITY_IAM"
endif
export IAM_CAPABILITIES

## Raw cloud formation template for the application
ifndef TEMPLATE_RAW
	override TEMPLATE_RAW=application.yaml
endif
export TEMPLATE_RAW

## Packaged cloud formation template
ifndef TEMPLATE_PACKAGED
	override TEMPLATE_PACKAGED=packaged.yaml
endif
export TEMPLATE_PACKAGED

## Set if defined (alias variable for ease of use)
ifdef tags
	override AWS_TAGS=$(tags)
	export AWS_TAGS
endif

## Set if defined (alias variable for ease of use)
ifdef bucket
	override APPLICATION_BUCKET=$(bucket)
	export APPLICATION_BUCKET
endif

## Set if defined (alias variable for ease of use)
ifdef domain
	override APPLICATION_DOMAIN_NAME=$(domain)
	export APPLICATION_DOMAIN_NAME
endif

## Set if defined (alias variable for ease of use)
ifdef stage
	override APPLICATION_STAGE_NAME=$(stage)
	export APPLICATION_STAGE_NAME
endif

## Set if defined (alias variable for ease of use)
ifdef application
	override APPLICATION_NAME=$(application)
	export APPLICATION_NAME
endif

## Set if defined (alias variable for ease of use)
ifdef feature
	override APPLICATION_FEATURE_NAME=$(feature)
	export APPLICATION_FEATURE_NAME
endif

## Set if defined (alias variable for ease of use)
ifdef application_domain_name
	override APPLICATION_DOMAIN_NAME=$(application_domain_name)
	export APPLICATION_DOMAIN_NAME
endif

.PHONY: aws-param-zone
aws-param-zone: ## Returns the ssm location for the host zone id
	@test $(domain)
	@echo "/$(domain)/zone_id"

.PHONY: aws-param-certificate
aws-param-certificate: ## Returns the ssm location for the domain ssl certificate id
	@test $(domain)
	@echo "/$(domain)/certificate_id"

.PHONY: aws-param-vpc-id
aws-param-vpc-id: ## Returns the ssm location for the vpc id
	@test $(vpc_name)
	@echo "/$(vpc_name)/vpc_id"

.PHONY: aws-param-vpc-private
aws-param-vpc-private: ## Returns the ssm location for the vpc private subnets
	@test $(vpc_name)
	@echo "/$(vpc_name)/private_subnets"

.PHONY: aws-param-vpc-public
aws-param-vpc-public: ## Returns the ssm location for the vpc public subnets
	@test $(vpc_name)
	@echo "/$(vpc_name)/public_subnets"

.PHONY: aws-param-vpc-public-subnet-1
aws-param-vpc-public-subnet-1: ## Returns the ssm location for the public subnet 1
	@test $(vpc_name)
	@echo "/$(vpc_name)/public_subnet_1"

.PHONY: aws-param-vpc-public-subnet-2
aws-param-vpc-public-subnet-2: ## Returns the ssm location for the public subnet 2
	@test $(vpc_name)
	@echo "/$(vpc_name)/public_subnet_2"

.PHONY: aws-param-vpc-private-subnet-1
aws-param-vpc-private-subnet-1: ## Returns the ssm location for the private subnet 1
	@test $(vpc_name)
	@echo "/$(vpc_name)/private_subnet_1"

.PHONY: aws-param-vpc-private-subnet-2
aws-param-vpc-private-subnet-2: ## Returns the ssm location for the private subnet 2
	@test $(vpc_name)
	@echo "/$(vpc_name)/private_subnet_2"

.PHONY: aws-param-dockerhub
aws-param-dockerhub: ## Returns the ssm location for the DockerHub ARN
	@test $(APPLICATION_NAME)
	@test $(APPLICATION_STAGE_NAME)
	@echo "/$(APPLICATION_STAGE_NAME)/$(APPLICATION_NAME)/dockerhub"

.PHONY: create-env-key
create-env-key: ## Creates a new key in KMS for a new stage
	@test $(APPLICATION_NAME)
	@test $(APPLICATION_STAGE_NAME)
	@$(eval kms_key_id := $(shell aws kms create-key --description "Used to encrypt environment variables for $(APPLICATION_NAME)" --query 'KeyMetadata.KeyId' --output text))
	@aws kms enable-key-rotation --key-id $(kms_key_id)
	@$(eval param_location := $(shell $(MAKE) env-key-location app=$(APPLICATION_NAME) stage=$(APPLICATION_STAGE_NAME) ))
	@aws kms create-alias --alias-name "alias/$(APPLICATION_NAME)/$(APPLICATION_STAGE_NAME)" --target-key-id $(kms_key_id)
	@$(MAKE) save-param param_name="$(param_location)" param_value=$(kms_key_id)
	@echo "Saved parameter: $(param_location) with key id: $(kms_key_id)"

.PHONY: create-secret
create-secret: ## Creates an secret into AWS SecretsManager
	@# Example: make create-secret name='production/test' description='This is a test' secret_value='{\"Key\":\"my_key\",\"Another\":\"value\"}' kms_key_id=b329...
	@test "$(name)"
	@test "$(description)"
	@test "$(secret_value)"
	@test $(kms_key_id)
	@aws secretsmanager create-secret \
		--name "$(name)" \
		--description "$(description)" \
		--kms-key-id $(kms_key_id) \
		--secret-string "$(secret_value)"

.PHONY: decrypt
decrypt: ## Decrypts data using a KMY Key ID (awscli v2)
	@# Example: make decrypt decrypt_value=AQICAHgrSMx+3O7...
	@test "$(decrypt_value)"
	@aws kms decrypt --ciphertext-blob "$(decrypt_value)" --output text --query Plaintext | base64 --decode

.PHONY: decrypt-deprecated
decrypt-deprecated: ## Decrypts data using a KMY Key ID (awscli v1)
	@# Example: make decrypt decrypt_value=AQICAHgrSMx+3O7...
	@test "$(decrypt_value)"
	@echo $(decrypt_value) | base64 --decode >> tempfile
	@aws kms decrypt --ciphertext-blob fileb://tempfile --output text --query Plaintext | base64 --decode
	@rm -rf tempfile

.PHONY: env-key-location
env-key-location: ## Returns the environment encryption key location
	@test $(app)
	@test $(stage)
	@echo "/$(app)/$(stage)/kms_key_id"

.PHONY: encrypt
encrypt: ## Encrypts data using a KMY Key ID (awscli v2)
	@# Example make encrypt kms_key_id=b329... encrypt_value=YourSecret
	@test $(kms_key_id)
	@test "$(encrypt_value)"
	@aws kms encrypt --output text --query CiphertextBlob --key-id $(kms_key_id) --plaintext "$(shell echo "$(encrypt_value)" | base64)"

.PHONY: invalidate-cache
invalidate-cache: ## Invalidates a cloudfront cache based on path
	@test $(APPLICATION_DISTRIBUTION_ID)
	@aws cloudfront create-invalidation --distribution-id $(APPLICATION_DISTRIBUTION_ID) --paths "/*"

.PHONY: package
package: ## Process the CF template and prepare for deployment
	@SAM_CLI_TELEMETRY=0 sam package \
        --template-file $(TEMPLATE_RAW)  \
        --output-template-file $(TEMPLATE_PACKAGED) \
        --s3-bucket $(APPLICATION_BUCKET) \
        --s3-prefix $(APPLICATION_BUCKET_PREFIX) \
        --region $(AWS_REGION)

.PHONY: save-host-info
save-host-info: ## Saves the host information for a given domain
	@test $(domain)
	@test $(zone_id)
	@$(MAKE) save-param param_name="/$(domain)/zone_id" param_value=$(zone_id)

.PHONY: save-domain-info
save-domain-info: ## Saves the zone id and the ssl id for use by CloudFormation
	@test $(domain)
	@test $(zone_id)
	@test $(certificate_id)
	@$(MAKE) save-param param_name="/$(domain)/zone_id" param_value=$(zone_id)
	@$(MAKE) save-param param_name="/$(domain)/certificate_id" param_value=$(certificate_id)

.PHONY: save-vpc-info
save-vpc-info: ## Saves the VPC id and the subnet IDs for use by CloudFormation
	@test $(vpc_name)
	@test $(vpc_id)
	@test $(public_subnet_1)
	@test $(public_subnet_2)
	@test $(private_subnet_1)
	@test $(private_subnet_2)
	@test $(private_subnets)
	@test $(public_subnets)
	@$(MAKE) save-param param_name="/$(vpc_name)/vpc_id" param_value=$(vpc_id)
	@$(MAKE) save-param param_name="/$(vpc_name)/public_subnet_1" param_value=$(public_subnet_1)
	@$(MAKE) save-param param_name="/$(vpc_name)/public_subnet_2" param_value=$(public_subnet_2)
	@$(MAKE) save-param param_name="/$(vpc_name)/private_subnet_1" param_value=$(private_subnet_1)
	@$(MAKE) save-param param_name="/$(vpc_name)/private_subnet_2" param_value=$(private_subnet_2)
	@$(MAKE) save-param-list param_name="/$(vpc_name)/private_subnets" param_value=$(private_subnets)
	@$(MAKE) save-param-list param_name="/$(vpc_name)/public_subnets" param_value=$(public_subnets)

.PHONY: save-param
save-param: ## Saves a plain-text string parameter in SSM
	@# Example: make save-param param_name='test' param_value='This is a test'
	@test "$(param_value)"
	@test "$(param_name)"
	@aws ssm put-parameter --name "$(param_name)" --value "$(param_value)" --type String --overwrite

.PHONY: save-param-list
save-param-list: ## Saves a list of strings (entry1,entry2,entry3) as a parameter in SSM
	@# Example: make save-param-list param_name='test' param_value='entry1,entry2,entry3'
	@test "$(param_value)"
	@test "$(param_name)"
	@aws ssm put-parameter --name "$(param_name)" --value "$(param_value)" --type StringList --overwrite

.PHONY: save-param-encrypted
save-param-encrypted: ## Saves an encrypted string value as a parameter in SSM
	@# Example: make save-param-encrypted param_name='test' param_value='This is a test' kms_key_id=b329...
	@test "$(param_value)"
	@test "$(param_name)"
	@test $(kms_key_id)
	@aws ssm put-parameter \
       --type String  \
       --overwrite  \
       --name "$(param_name)" \
       --value "$(shell $(MAKE) encrypt kms_key_id=$(kms_key_id) encrypt_value="$(param_value)")"

.PHONY: upload-files
upload-files: ## Upload/puts files into S3 bucket
	@test "$(source)"
	@test "$(destination)"
	@test $(APPLICATION_BUCKET)
	@aws s3 cp $(source) s3://$(APPLICATION_BUCKET)/$(destination) --recursive

.PHONY: update-secret
update-secret: ## Updates an existing secret in AWS SecretsManager
	@# Example: make update-secret name='production/test' secret_value='{\"Key\":\"my_key\",\"Another\":\"value\"}'
	@test "$(name)"
	@test "$(secret_value)"
	@aws secretsmanager update-secret \
		--secret-id "$(name)" \
		--secret-string "$(secret_value)"

.PHONY: teardown
teardown: ## Deletes the entire stack
	@test $(APPLICATION_STACK_NAME)
	@aws cloudformation delete-stack --stack-name $(APPLICATION_STACK_NAME)
