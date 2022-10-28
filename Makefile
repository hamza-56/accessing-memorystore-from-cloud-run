PROJECT_ID=$(shell gcloud config get-value core/project)
APP=cloud-run-app
VPC_NETWORK=hamza

all:
	@echo "do-all             - Build all the test components"
	@echo "build              - Build the docker image"
	@echo "deploy             - Deploy the image to Cloud Run"
	@echo "create-memorystore - Create the Memorystore instance"
	@echo "create-connection  - Create the VPC Access Connector"
	@echo "clean              - Delete all resources in GCP created by these tests"

create-vpc-network:
	gcloud compute networks create $(VPC_NETWORK) \
		--subnet-mode=auto \
		--bgp-routing-mode=regional \
		--mtu=1460

create-connection:
	gcloud compute networks vpc-access connectors create my-vpc-connector \
		--network $(VPC_NETWORK) \
		--region us-central1 \
		--range 10.8.0.0/28

create-firewall-rules:
	gcloud compute firewall-rules create $(VPC_NETWORK)-allow-internal \
		--action=ALLOW \
		--direction=INGRESS \
		--network=$(VPC_NETWORK)  \
		--priority=1000 \
		--rules=tcp:0-65535,udp:0-65535,icmp \
		--source-ranges=10.128.0.0/9
	gcloud compute firewall-rules create $(VPC_NETWORK)-allow-icmp \
		--action=ALLOW \
		--direction=INGRESS \
		--network=$(VPC_NETWORK)  \
		--priority=1000 \
		--rules=icmp
	gcloud compute firewall-rules create $(VPC_NETWORK)-allow-rdp \
		--action=ALLOW \
		--direction=INGRESS \
		--network=$(VPC_NETWORK)  \
		--priority=1000 \
		--rules=tcp:3389
	gcloud compute firewall-rules create $(VPC_NETWORK)-allow-ssh \
		--action=ALLOW \
		--direction=INGRESS \
		--network=$(VPC_NETWORK)  \
		--priority=1000 \
		--rules=tcp:22

create-memorystore:
	gcloud redis instances create redis1 --region us-central1 --network $(VPC_NETWORK)

deploy:
	REDIS_IP=$(shell gcloud redis instances describe redis1 --region us-central1 --format='value(host)'); \
	gcloud run deploy $(APP) \
		--image gcr.io/$(PROJECT_ID)/$(APP) \
		--max-instances 1 \
		--platform managed \
		--region us-central1 \
		--vpc-connector my-vpc-connector \
		--allow-unauthenticated \
		--set-env-vars "REDIS_IP=$$REDIS_IP"
	@url=$(shell gcloud run services describe cloud-run-app --format='value(status.url)' --region us-central1 --platform managed); \
	echo "Target URL = $$url"

build:
	gcloud builds submit --tag gcr.io/$(PROJECT_ID)/$(APP)

do-all: create-vpc-network create-firewall-rules create-memorystore create-connection build deploy
	@echo "All done!"

clean:
	-gcloud run services delete $(APP) --platform managed --region us-central1 --quiet
	-gcloud container images delete gcr.io/$(PROJECT_ID)/$(APP):latest --quiet
	-gcloud compute networks vpc-access connectors delete my-vpc-connector --region us-central1 --quiet
	-gcloud redis instances delete redis1 --region us-central1 --quiet
	-gcloud compute firewall-rules delete $(VPC_NETWORK)-allow-internal --quiet
	-gcloud compute firewall-rules delete $(VPC_NETWORK)-allow-icmp --quiet
	-gcloud compute firewall-rules delete $(VPC_NETWORK)-allow-rdp --quiet
	-gcloud compute firewall-rules delete $(VPC_NETWORK)-allow-ssh --quiet
	-gcloud compute networks delete $(VPC_NETWORK) --quiet
