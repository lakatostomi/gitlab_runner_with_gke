PROJECT_ID := my-project-id
REGION := europe-west1
GITLAB_RUNNER_NAME := gke-runner
NAMESPACE := gitlab-runner
K8S_SERVICE_ACCOUNT := runner-sa
GCP_PROJECT_SA := gitlab-runner-sa
GCS_CACHE_SUFFIX := gitlab-runner-cache-bucket

deploy_cluster:
	terraform plan
	terraform apply --auto-approve -var="project_id=$(PROJECT_ID)"

config_cluster: deploy_cluster
	gcloud container clusters get-credentials gitlab-cluster --zone=$(REGION)
	kubectl create namespace $(NAMESPACE)
	kubectl create serviceaccount $(K8S_SERVICE_ACCOUNT) -n $(NAMESPACE)
	kubectl annotate serviceaccount $(K8S_SERVICE_ACCOUNT) \
  		-n $(NAMESPACE) \
  		iam.gke.io/gcp-service-account=$(GCP_PROJECT_SA)@$(PROJECT_ID).iam.gserviceaccount.com	

deploy_runner: config_cluster
	helm repo add gitlab https://charts.gitlab.io
	helm repo update

	kubectl apply -f gitlab-runner-role.yaml
	kubectl apply -f gitlab-role-binding.yaml
	kubectl apply -f gitlab-runner-secret.yaml

	helm install gitlab-runner gitlab/gitlab-runner \
  		--namespace $(NAMESPACE) \
		--version 0.87.0 \
		--set name="$(GITLAB_RUNNER_NAME)" \
		--set gitlabRunner.cacheBucketName="$(PROJECT_ID)-$(GCS_CACHE_SUFFIX)" \
		--set gitlabRunner.namespace="$(NAMESPACE)" \
		--set namespace="$(NAMESPACE)" \
		--set gitlabRunner.service_account="$(K8S_SERVICE_ACCOUNT)" \
  		-f values.yaml

update_runner:
	helm upgrade gitlab-runner gitlab/gitlab-runner \
  		--namespace $(NAMESPACE) \
		--version 0.87.0 \
		--set name="$(GITLAB_RUNNER_NAME)" \
		--set gitlabRunner.cacheBucketName="$(PROJECT_ID)-$(GCS_CACHE_SUFFIX)" \
		--set gitlabRunner.namespace="$(NAMESPACE)" \
		--set namespace="$(NAMESPACE)" \
		--set gitlabRunner.service_account="$(K8S_SERVICE_ACCOUNT)" \
  		-f values.yaml

test:
	helm template gitlab-runner gitlab/gitlab-runner \
  		--namespace $(NAMESPACE) \
		--version 0.87.0 \
		--set name="$(GITLAB_RUNNER_NAME)" \
		--set gitlabRunner.cacheBucketName="$(PROJECT_ID)-$(GCS_CACHE_SUFFIX)" \
		--set gitlabRunner.namespace="$(NAMESPACE)" \
		--set namespace="$(NAMESPACE)" \
		--set gitlabRunner.service_account="$(K8S_SERVICE_ACCOUNT)" \
  		-f values.yaml

clean_up:
	helm delete --namespace $(NAMESPACE) gitlab-runner
	terraform destroy --auto-approve		