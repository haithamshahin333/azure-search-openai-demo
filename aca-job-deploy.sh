#!/bin/bash

az extension add -n containerapp

# Variables
### SET ENV VARS from .env.local


echo "Creating Storage Account Queues on the existing storage account"
# Create Storage Account Queues on the existing storage account
az storage queue create --name $QUEUE_NAME --account-name $STORAGE_ACCOUNT_NAME --auth-mode login
az storage queue create --name $DEADLETTER_QUEUE_NAME --account-name $STORAGE_ACCOUNT_NAME --auth-mode login
az storage container create --name $INGEST_CONTAINER_NAME --account-name $STORAGE_ACCOUNT_NAME --auth-mode login

azd env set AZURE_STORAGE_ACCOUNT_KB_NAME $STORAGE_ACCOUNT_NAME
azd env set AZURE_STORAGE_CONTAINER_KB_NAME $INGEST_CONTAINER_NAME

# Create private endpoint for storage account queues
az network private-endpoint create \
    --name storageAccountPrivateEndpoint \
    --resource-group $RESOURCE_GROUP \
    --vnet-name $VNET_NAME \
    --subnet $SUBNET_NAME \
    --private-connection-resource-id $(az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $RESOURCE_GROUP --query id --output tsv) \
    --group-id queue \
    --connection-name storageAccountPrivateConnection

echo "Creating Private DNS Zone for Storage Account Queues..."
# Create a Private DNS Zone for Storage Account Queues
DNS_ZONE_NAME=privatelink.queue.core.windows.net
az network private-dns zone create --resource-group $RESOURCE_GROUP --name $DNS_ZONE_NAME

echo "Linking Private DNS Zone to VNet..."
# Link the Private DNS Zone to the VNet
az network private-dns link vnet create \
    --resource-group $RESOURCE_GROUP \
    --zone-name $DNS_ZONE_NAME \
    --name myDNSLink \
    --virtual-network $VNET_NAME \
    --registration-enabled false

# Configure DNS settings on the private endpoint
az network private-endpoint dns-zone-group create \
    --resource-group $RESOURCE_GROUP \
    --endpoint-name storageAccountPrivateEndpoint \
    --name storageAccountPrivateDnsZoneGroup \
    --private-dns-zone $DNS_ZONE_NAME \
    --zone-name $DNS_ZONE_NAME


echo "Create an event grid subscription to route BlobCreated and BlobDeleted events to the storage account queue..."
# Create an event grid system topic with a system assigned managed identity
az eventgrid system-topic create \
    --name $STORAGE_ACCOUNT_NAME-system-topic \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --topic-type Microsoft.Storage.StorageAccounts \
    --identity systemassigned \
    --source /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME

# Get the system assigned managed identity for the system topic and assign it the Storage Queue Data Message Sender role
SYSTEM_TOPIC_ID=$(az eventgrid system-topic show --name $STORAGE_ACCOUNT_NAME-system-topic --resource-group $RESOURCE_GROUP --query id --output tsv)
STORAGE_ACCOUNT_ID=$(az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $RESOURCE_GROUP --query id --output tsv)
SYSTEM_TOPIC_OBJECT_ID=$(az eventgrid system-topic show --name $STORAGE_ACCOUNT_NAME-system-topic --resource-group $RESOURCE_GROUP --query identity.principalId --output tsv)
# assign the role
az role assignment create --assignee $SYSTEM_TOPIC_OBJECT_ID --role "Storage Queue Data Message Sender" --scope $STORAGE_ACCOUNT_ID

# Create an event grid subscription to route BlobCreated and BlobDeleted events to the storage account queue
az eventgrid system-topic event-subscription create \
    --name $STORAGE_ACCOUNT_NAME-queue-subscription \
    --system-topic-name $STORAGE_ACCOUNT_NAME-system-topic \
    --resource-group $RESOURCE_GROUP \
    --endpoint-type storagequeue \
    --endpoint /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME/queueservices/default/queues/$QUEUE_NAME \
    --included-event-types Microsoft.Storage.BlobCreated Microsoft.Storage.BlobDeleted \
    --subject-begins-with /blobServices/default/containers/$INGEST_CONTAINER_NAME \
    --event-delivery-schema eventgridschema

echo "GO INTO PORTAL AND UPDATE SYSTEM MI AND THE TTL FOR THE MESSAGE QUEUE"
sleep 1000



echo "Creating Azure Container Registry (ACR)..."
# Create an Azure Container Registry (ACR) with private endpoint and disable public access
az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Premium --location $LOCATION --public-network-enabled false

echo "Creating private endpoint for ACR..."
# Create a private endpoint for the ACR
ACR_ID=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query id --output tsv)
az network private-endpoint create \
    --name acrPrivateEndpoint \
    --resource-group $RESOURCE_GROUP \
    --vnet-name $VNET_NAME \
    --subnet $SUBNET_NAME \
    --private-connection-resource-id $ACR_ID \
    --group-id registry \
    --connection-name acrPrivateConnection

echo "Creating Private DNS Zone..."
# Create a Private DNS Zone
DNS_ZONE_NAME=privatelink.azurecr.io
az network private-dns zone create --resource-group $RESOURCE_GROUP --name $DNS_ZONE_NAME

echo "Linking Private DNS Zone to VNet..."
# Link the Private DNS Zone to the VNet
az network private-dns link vnet create \
    --resource-group $RESOURCE_GROUP \
    --zone-name $DNS_ZONE_NAME \
    --name myDNSLink \
    --virtual-network $VNET_NAME \
    --registration-enabled false

# Configure DNS settings on the private endpoint
az network private-endpoint dns-zone-group create \
    --resource-group $RESOURCE_GROUP \
    --endpoint-name acrPrivateEndpoint \
    --name acrPrivateDnsZoneGroup \
    --private-dns-zone $DNS_ZONE_NAME \
    --zone-name $DNS_ZONE_NAME



echo "Logging in to ACR..."
# Log in to the ACR
az acr login --name $ACR_NAME
az role assignment create --assignee $MANAGED_IDENTITY_OBJECT_ID --role "AcrPush" --scope $ACR_ID

echo "PUSHING IMAGE TO ACR"
docker build . -t $ACR_NAME.azurecr.io/$IMAGE_NAME:latest -f $DOCKERFILE_PATH
docker push $ACR_NAME.azurecr.io/$IMAGE_NAME:latest

echo "Building Docker image and pushing to ACR..."
# Build the Docker image and push it to the ACR
az acr build . --registry $ACR_NAME --image $IMAGE_NAME:latest -f $DOCKERFILE_PATH




echo "Creating user-assigned managed identity..."
# Create a user-assigned managed identity
MANAGED_IDENTITY_ID=$(az identity create --resource-group $RESOURCE_GROUP --name $MANAGED_IDENTITY_NAME --query id --output tsv)
MANAGED_IDENTITY_OBJECT_ID=$(az identity show --resource-group $RESOURCE_GROUP --name $MANAGED_IDENTITY_NAME --query principalId --output tsv)
MANAGED_IDENTITY_CLIENT_ID=$(az identity show --resource-group $RESOURCE_GROUP --name $MANAGED_IDENTITY_NAME --query clientId --output tsv)


echo "Assigning ACR pull permissions to the managed identity..."
# Assign ACR pull permissions to the managed identity
ACR_ID=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query id --output tsv)

az role assignment create --assignee $MANAGED_IDENTITY_OBJECT_ID --role "AcrPull" --scope $ACR_ID

echo "Assigning Storage Blob Data Reader and Storage Queue Data Message Reader permissions to the managed identity..."
# Assign Storage Blob Data Reader and Storage Queue Data Message Reader permissions to the managed identity
STORAGE_ACCOUNT_ID=$(az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $RESOURCE_GROUP --query id --output tsv)
az role assignment create --assignee $MANAGED_IDENTITY_OBJECT_ID --role "Storage Blob Data Reader" --scope $STORAGE_ACCOUNT_ID
az role assignment create --assignee $MANAGED_IDENTITY_OBJECT_ID --role "Storage Queue Data Contributor" --scope $STORAGE_ACCOUNT_ID

COSMOS_DB_ACCOUNT_ID=$(az cosmosdb show --name $COSMOS_DB_ACCOUNT_NAME --resource-group $RESOURCE_GROUP --query id --output tsv)

echo "Assigning Cosmos DB Data Reader and Cosmos DB Operator permissions to the managed identity..."
# Assign Cosmos DB Data Reader and Cosmos DB Operator permissions to the managed identity
az cosmosdb sql role assignment create --resource-group $RESOURCE_GROUP --account-name $COSMOS_DB_ACCOUNT_NAME --role-definition-id 00000000-0000-0000-0000-000000000002 --principal-id $MANAGED_IDENTITY_OBJECT_ID --scope $COSMOS_DB_ACCOUNT_ID

echo "Assigning additional roles to the managed identity at the subscription scope..."
# Assign additional roles to the managed identity at the subscription scope
az role assignment create --assignee $MANAGED_IDENTITY_OBJECT_ID --role "Search Index Data Contributor" --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP
az role assignment create --assignee $MANAGED_IDENTITY_OBJECT_ID --role "Cognitive Services OpenAI Contributor" --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$OPENAI_RESOURCE_GROUP
az role assignment create --assignee $MANAGED_IDENTITY_OBJECT_ID --role "Search Index Data Reader" --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP
az role assignment create --assignee $MANAGED_IDENTITY_OBJECT_ID --role "Cognitive Services Data Contributor (Preview)" --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP
az role assignment create --assignee $MANAGED_IDENTITY_OBJECT_ID --role "Search Service Contributor" --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP

# Create a container app environment

# update aca subnet with Microsoft.App/environments delegation
az network vnet subnet update --name $CONTAINER_APP_SUBNET_NAME --vnet-name $VNET_NAME --resource-group $RESOURCE_GROUP --delegations "Microsoft.App/environments"

az containerapp env create \
    --enable-workload-profiles \
    --resource-group $RESOURCE_GROUP \
    --name $ENVIRONMENT \
    --location $LOCATION \
    --infrastructure-subnet-resource-id $(az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name $VNET_NAME --name $CONTAINER_APP_SUBNET_NAME --query id --output tsv) \
    --internal-only true

echo "Deploying container app job..."
# Deploy a container app job that is scaled by a storage queue
az containerapp job create \
    --name ingest-job \
    --resource-group $RESOURCE_GROUP \
    --image $ACR_NAME.azurecr.io/$IMAGE_NAME:latest \
    --registry-identity $MANAGED_IDENTITY_ID \
    --registry-server $ACR_NAME.azurecr.io \
    --environment $ENVIRONMENT \
    --cpu 0.5 \
    --memory 1.0Gi \
    --trigger-type Event \
    --max-executions 10 \
    --env-vars "AZURE_STORAGE_ACCOUNT_URL=$STORAGE_ACCOUNT_NAME.queue.core.windows.net" "AZURE_STORAGE_QUEUE_NAME=$QUEUE_NAME" "AZURE_STORAGE_DEADLETTER_QUEUE_NAME=$DEADLETTER_QUEUE_NAME" "CLOUD_ENVIRONMENT=Azure" "AZURE_CLIENT_ID=$MANAGED_IDENTITY_CLIENT_ID" "AZURE_STORAGE_ACCOUNT_KB_NAME=$STORAGE_ACCOUNT_NAME" "AZURE_STORAGE_CONTAINER_KB_NAME=$INGEST_CONTAINER_NAME" \
    --mi-user-assigned $MANAGED_IDENTITY_ID \
    --scale-rule-name azure-queue \
    --scale-rule-type azure-queue \
    --scale-rule-identity $MANAGED_IDENTITY_ID \
    --scale-rule-metadata "accountName=$STORAGE_ACCOUNT_NAME" "queueName=$QUEUE_NAME" "queueLength=10" "queueLengthStrategy=visibleonly" \
    --polling-interval 30

echo "Deployment completed."
