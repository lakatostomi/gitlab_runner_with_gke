PROJECT_ID := my-test-project-88
REGION := europe-west1
GITLAB_RUNNER_NAME := gke-runner
NAMESPACE := gitlab-runner
K8S_SERVICE_ACCOUNT := runner-sa
GCP_PROJECT_SA := gitlab-runner-project-sa
GCS_NAME := my-test-gitlab-runner-cache-bucket

config_cluster:
	gcloud container clusters get-credentials gitlab-cluster --zone=$(REGION) --project=$(PROJECT_ID)
	kubectl create namespace $(NAMESPACE)
	kubectl create serviceaccount $(K8S_SERVICE_ACCOUNT) -n $(NAMESPACE)
	kubectl annotate serviceaccount $(K8S_SERVICE_ACCOUNT) \
  		-n $(NAMESPACE) \
  		iam.gke.io/gcp-service-account=$(GCP_PROJECT_SA)@$(PROJECT_ID).iam.gserviceaccount.com

deploy_runner:
	helm repo add gitlab https://charts.gitlab.io
	helm repo update

	kubectl apply -f gitlab-runner-role.yaml
	kubectl apply -f gitlab-role-binding.yaml
	kubectl apply -f gitlab-runner-secret.yaml

	helm install gitlab-runner gitlab/gitlab-runner \
  		--namespace $(NAMESPACE) \
		--version 0.87.0 \
		--set name="$(GITLAB_RUNNER_NAME)" \
		--set gitlabRunner.cacheBucketName="$(GCS_NAME)" \
		--set gitlabRunner.namespace="$(NAMESPACE)" \
		--set namespace="$(NAMESPACE)" \
		--set gitlabRunner.service_account="$(K8S_SERVICE_ACCOUNT)" \
  		-f values.yaml

update_runner:
	helm upgrade gitlab-runner gitlab/gitlab-runner \
  		--namespace $(NAMESPACE) \
		--version 0.87.0 \
		--set name="$(GITLAB_RUNNER_NAME)" \
		--set gitlabRunner.cacheBucketName="$(GCS_NAME)" \
		--set gitlabRunner.namespace="$(NAMESPACE)" \
		--set namespace="$(NAMESPACE)" \
		--set gitlabRunner.service_account="$(K8S_SERVICE_ACCOUNT)" \
  		-f values.yaml

reinstall_runner:
	helm delete --namespace $(NAMESPACE) gitlab-runner
	helm install gitlab-runner gitlab/gitlab-runner \
  		--namespace $(NAMESPACE) \
		--version 0.87.0 \
		--set name="$(GITLAB_RUNNER_NAME)" \
		--set gitlabRunner.cacheBucketName="$(GCS_NAME)" \
		--set gitlabRunner.namespace="$(NAMESPACE)" \
		--set namespace="$(NAMESPACE)" \
		--set gitlabRunner.service_account="$(K8S_SERVICE_ACCOUNT)" \
  		-f values.yaml

verify:
	helm template gitlab-runner gitlab/gitlab-runner \
  		--namespace $(NAMESPACE) \
		--version 0.87.0 \
		--set name="$(GITLAB_RUNNER_NAME)" \
		--set gitlabRunner.cacheBucketName="$(GCS_NAME)" \
		--set gitlabRunner.namespace="$(NAMESPACE)" \
		--set namespace="$(NAMESPACE)" \
		--set gitlabRunner.service_account="$(K8S_SERVICE_ACCOUNT)" \
  		-f values.yaml

clean_up:
	helm delete --namespace $(NAMESPACE) gitlab-runner
	kubectl wait --for=delete pod -l app=gitlab-runner -n $(NAMESPACE) --timeout=300s		