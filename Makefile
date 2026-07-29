.PHONY: init plan deploy destroy test clean

init:
	@mkdir -p build
	@cd terraform && terraform init

plan:
	@cd terraform && terraform plan

deploy:
	@mkdir -p build
	@cd terraform && terraform apply -auto-approve

destroy:
	@cd terraform && terraform destroy -auto-approve

test:
	@cd terraform && terraform output -raw api_endpoint

clean:
	@rm -rf build .terraform *.tfstate *.tfstate.* terraform/.terraform terraform/*.tfstate terraform/*.tfstate.*
