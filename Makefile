PROJECT_ID=$(shell gcloud config get-value core/project)
REGION=us-central1
APP=cloud-run-app
VPC_NETWORK=hamza
VPC_CONNECTOR_NAME=my-vpc-connector
REDIS_INSTANCE_NAME=redis1
IP_RANGE_NAME=google-managed-services-dev
SQL_INSTANCE_NAME=quickstart-instance
DB_NAME=quickstart_db
DB_ROOT_PASS=ROOT_PASSWORD
DB_USER=hamza
DB_PASS=PASSWORD
DB_PORT=5432


all:
	@echo "do-all						- Build all the test components"
	@echo "build						- Build the docker image"
	@echo "deploy						- Deploy the image to Cloud Run"
	@echo "create-vpc-network			- Create VPC Network"
	@echo "create-vpc-firewall-rules	- Create firewall rules for VPC"
	@echo "reserve-ip-range				- Reserve IP range for VPC Peering"
	@echo "setup-vpc-peering			- Setup VPC Peering"
	@echo "create-memorystore			- Create the Memorystore instance"
	@echo "create-vpc-connector			- Create the VPC Access Connector"
	@echo "create-cloud-sql-instance	- Create Cloud SQL Instance"
	@echo "clean						- Delete all resources in GCP created by these tests"

create-vpc-network:
	gcloud compute networks create $(VPC_NETWORK) \
		--subnet-mode=auto \
		--bgp-routing-mode=regional \
		--mtu=1460

create-vpc-connector:
	gcloud compute networks vpc-access connectors create $(VPC_CONNECTOR_NAME) \
		--network $(VPC_NETWORK) \
		--region $(REGION) \
		--range 10.8.0.0/28

create-vpc-firewall-rules:
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
	gcloud redis instances create $(REDIS_INSTANCE_NAME) --region $(REGION) --network $(VPC_NETWORK)

reserve-ip-range:
	gcloud compute addresses create $(IP_RANGE_NAME) \
		--global --purpose=VPC_PEERING --prefix-length=16 \
		--description="Peering range for Google" --network=$(VPC_NETWORK)

setup-vpc-peering:
	gcloud services vpc-peerings connect --service=servicenetworking.googleapis.com \
		--ranges=$(IP_RANGE_NAME) --network=$(VPC_NETWORK)

create-cloud-sql-instance:	
	gcloud sql instances create $(SQL_INSTANCE_NAME) \
		--database-version=POSTGRES_13 \
		--cpu=1 \
		--memory=4GB \
		--region=$(REGION) \
		--root-password=$(DB_ROOT_PASS) \
		--no-assign-ip \
		--network=$(VPC_NETWORK)
	# gcloud sql instances patch quickstart-instance --require-ssl
	gcloud sql databases create $(DB_NAME) --instance=$(SQL_INSTANCE_NAME)
	gcloud sql users create $(DB_USER) \
		--instance=$(SQL_INSTANCE_NAME) \
		--password=$(DB_PASS)

deploy:
	REDIS_IP=$(shell gcloud redis instances describe $(REDIS_INSTANCE_NAME) --region $(REGION) --format='value(host)'); \
	CLOUD_SQL_PRIVATE_IP=$(shell gcloud sql instances describe $(SQL_INSTANCE_NAME) --format='get(ipAddresses[0].ipAddress)'); \
	gcloud run deploy $(APP) \
		--image gcr.io/$(PROJECT_ID)/$(APP) \
		--max-instances 1 \
		--platform managed \
		--region $(REGION) \
		--vpc-connector $(VPC_CONNECTOR_NAME) \
		--allow-unauthenticated \
		--set-env-vars "REDIS_IP=$$REDIS_IP" \
		--set-env-vars "INSTANCE_HOST=$$CLOUD_SQL_PRIVATE_IP" \
		--set-env-vars "DB_NAME=$(DB_NAME)" \
		--set-env-vars "DB_USER=$(DB_USER)" \
		--set-env-vars "DB_PASS=$(DB_PASS)" \
		--set-env-vars "DB_PORT=$(DB_PORT)"
		# --add-cloudsql-instances $(SQL_INSTANCE_NAME)
	@url=$(shell gcloud run services describe cloud-run-app --format='value(status.url)' --region $(REGION) --platform managed); \
	echo "Target URL = $$url"

build:
	gcloud builds submit --tag gcr.io/$(PROJECT_ID)/$(APP)

do-all: create-vpc-network create-vpc-firewall-rules create-memorystore create-vpc-connector reserve-ip-range setup-vpc-peering create-cloud-sql-instance build deploy
	@echo "All done!"

clean:
	-gcloud run services delete $(APP) --platform managed --region $(REGION) --quiet
	-gcloud container images delete gcr.io/$(PROJECT_ID)/$(APP):latest --quiet
	-gcloud redis instances delete $(REDIS_INSTANCE_NAME) --region $(REGION) --quiet
	-gcloud sql instances delete $(SQL_INSTANCE_NAME) --quiet
	-gcloud compute networks vpc-access connectors delete $(VPC_CONNECTOR_NAME) --region $(REGION) --quiet
	-gcloud services vpc-peerings delete --service=servicenetworking.googleapis.com --network=$(VPC_NETWORK) --quiet
	-gcloud compute addresses delete $(IP_RANGE_NAME) --region $(REGION) --quiet
	-gcloud compute firewall-rules delete $(VPC_NETWORK)-allow-internal --quiet
	-gcloud compute firewall-rules delete $(VPC_NETWORK)-allow-icmp --quiet
	-gcloud compute firewall-rules delete $(VPC_NETWORK)-allow-rdp --quiet
	-gcloud compute firewall-rules delete $(VPC_NETWORK)-allow-ssh --quiet
	-gcloud compute networks delete $(VPC_NETWORK) --quiet
