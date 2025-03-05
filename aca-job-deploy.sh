#!/bin/bash
az extension add -n containerapp

echo "Creating Storage Account Queues on the existing storage account"
# Create Storage Account Queues on the existing storage account
az storage queue create --name $AZURE_INGEST_QUEUE_NAME --account-name $AZURE_STORAGE_ACCOUNT --auth-mode login
az storage queue create --name $AZURE_INGEST_DEADLETTER_QUEUE_NAME --account-name $AZURE_STORAGE_ACCOUNT --auth-mode login
az storage container create --name $AZURE_INGEST_STG_CONTAINER_NAME --account-name $AZURE_STORAGE_ACCOUNT --auth-mode login

azd env set AZURE_STORAGE_ACCOUNT_KB_NAME $AZURE_STORAGE_ACCOUNT
azd env set AZURE_STORAGE_CONTAINER_KB_NAME $AZURE_INGEST_STG_CONTAINER_NAME

# Create private endpoint for storage account queues
echo "Creating private endpoint for storage account queues..."
az network private-endpoint create \
    --name storageAccountPrivateEndpoint \
    --resource-group $AZURE_RESOURCE_GROUP \
    --vnet-name $AZURE_VNET_NAME \
    --subnet $AZURE_BACKEND_SUBNET_ID \
    --private-connection-resource-id $(az storage account show --name $AZURE_STORAGE_ACCOUNT --resource-group $AZURE_RESOURCE_GROUP --query id --output tsv) \
    --group-id queue \
    --connection-name storageAccountPrivateConnection

echo "Creating Private DNS Zone for Storage Account Queues..."
DNS_ZONE_NAME=privatelink.queue.core.windows.net
az network private-dns zone create --resource-group $AZURE_RESOURCE_GROUP --name $DNS_ZONE_NAME

echo "Linking Private DNS Zone to VNet..."
az network private-dns link vnet create \
    --resource-group $AZURE_RESOURCE_GROUP \
    --zone-name $DNS_ZONE_NAME \
    --name myDNSLink \
    --virtual-network $AZURE_VNET_NAME \
    --registration-enabled false

# Configure DNS settings on the private endpoint
echo "Configuring DNS settings on the private endpoint..."
az network private-endpoint dns-zone-group create \
    --resource-group $AZURE_RESOURCE_GROUP \
    --endpoint-name storageAccountPrivateEndpoint \
    --name storageAccountPrivateDnsZoneGroup \
    --private-dns-zone $DNS_ZONE_NAME \
    --zone-name $DNS_ZONE_NAME


echo "Create an event grid subscription to route BlobCreated and BlobDeleted events to the storage account queue..."
# Create an event grid system topic with a system assigned managed identity
az eventgrid system-topic create \
    --name $AZURE_STORAGE_ACCOUNT-system-topic \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_LOCATION \
    --topic-type Microsoft.Storage.StorageAccounts \
    --identity systemassigned \
    --source /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$AZURE_STORAGE_ACCOUNT

# Get the system assigned managed identity for the system topic and assign it the Storage Queue Data Message Sender role
SYSTEM_TOPIC_ID=$(az eventgrid system-topic show --name $AZURE_STORAGE_ACCOUNT-system-topic --resource-group $AZURE_RESOURCE_GROUP --query id --output tsv)
STORAGE_ACCOUNT_ID=$(az storage account show --name $AZURE_STORAGE_ACCOUNT --resource-group $AZURE_RESOURCE_GROUP --query id --output tsv)
SYSTEM_TOPIC_OBJECT_ID=$(az eventgrid system-topic show --name $AZURE_STORAGE_ACCOUNT-system-topic --resource-group $AZURE_RESOURCE_GROUP --query identity.principalId --output tsv)
# assign the role
az role assignment create --assignee $SYSTEM_TOPIC_OBJECT_ID --role "Storage Queue Data Message Sender" --scope $STORAGE_ACCOUNT_ID

# Create an event grid subscription to route BlobCreated and BlobDeleted events to the storage account queue
# az eventgrid system-topic event-subscription create \
#     --name $AZURE_STORAGE_ACCOUNT-queue-subscription \
#     --system-topic-name $AZURE_STORAGE_ACCOUNT-system-topic \
#     --resource-group $AZURE_RESOURCE_GROUP \
#     --endpoint-type storagequeue \
#     --endpoint /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$AZURE_STORAGE_ACCOUNT/queueservices/default/queues/AZURE_INGEST_QUEUE_NAME \
#     --included-event-types Microsoft.Storage.BlobCreated Microsoft.Storage.BlobDeleted \
#     --subject-begins-with /blobServices/default/containers/$AZURE_INGEST_STG_CONTAINER_NAME \
#     --event-delivery-schema eventgridschema

az eventgrid event-subscription create \
    --name $AZURE_STORAGE_ACCOUNT-queue-subscription \
    --source-resource-id $STORAGE_ACCOUNT_ID \
    --delivery-identity-endpoint-type storagequeue \
    --delivery-identity-endpoint /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$AZURE_STORAGE_ACCOUNT/queueservices/default/queues/$AZURE_INGEST_QUEUE_NAME \
    --included-event-types Microsoft.Storage.BlobCreated Microsoft.Storage.BlobDeleted \
    --subject-begins-with /blobServices/default/containers/$AZURE_INGEST_STG_CONTAINER_NAME \
    --event-delivery-schema eventgridschema \
    --qttl 604800 \
    --delivery-identity systemassigned





echo "Creating Azure Container Registry (ACR)..."
# Create an Azure Container Registry (ACR) with private endpoint and disable public access
az acr create --resource-group $AZURE_RESOURCE_GROUP --name $AZURE_INGEST_ACR_NAME --sku Premium --location $AZURE_LOCATION --public-network-enabled false

echo "Creating private endpoint for ACR..."
# Create a private endpoint for the ACR
ACR_ID=$(az acr show --name $AZURE_INGEST_ACR_NAME --resource-group $AZURE_RESOURCE_GROUP --query id --output tsv)
az network private-endpoint create \
    --name acrPrivateEndpoint \
    --resource-group $AZURE_RESOURCE_GROUP \
    --vnet-name $AZURE_VNET_NAME \
    --subnet $AZURE_BACKEND_SUBNET_ID \
    --private-connection-resource-id $ACR_ID \
    --group-id registry \
    --connection-name acrPrivateConnection

echo "Creating Private DNS Zone..."
# Create a Private DNS Zone
DNS_ZONE_NAME=privatelink.azurecr.io
az network private-dns zone create --resource-group $AZURE_RESOURCE_GROUP --name $DNS_ZONE_NAME

echo "Linking Private DNS Zone to VNet..."
# Link the Private DNS Zone to the VNet
az network private-dns link vnet create \
    --resource-group $AZURE_RESOURCE_GROUP \
    --zone-name $DNS_ZONE_NAME \
    --name myDNSLink \
    --virtual-network $AZURE_VNET_NAME \
    --registration-enabled false

# Configure DNS settings on the private endpoint
az network private-endpoint dns-zone-group create \
    --resource-group $AZURE_RESOURCE_GROUP \
    --endpoint-name acrPrivateEndpoint \
    --name acrPrivateDnsZoneGroup \
    --private-dns-zone $DNS_ZONE_NAME \
    --zone-name $DNS_ZONE_NAME



# Create an Azure Cosmosdb Nosql database and container that is serverless
echo "Creating Azure Cosmos DB account..."
# Create an Azure Cosmos DB account nosql
az cosmosdb create \
    --name $AZURE_INGEST_COSMOS_DB_ACCOUNT_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --locations regionName=$AZURE_LOCATION \
    --capabilities EnableServerless \
    --kind GlobalDocumentDB \
    --public-network-access Disabled

echo "Creating Cosmos DB database and container..."

az cosmosdb sql database create \
    --account-name $AZURE_INGEST_COSMOS_DB_ACCOUNT_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --name $AZURE_INGEST_COSMOS_DB_DATABASE_NAME

echo "Creating Cosmos DB container..."
az cosmosdb sql container create \
    --account-name $AZURE_INGEST_COSMOS_DB_ACCOUNT_NAME \
    --database-name $AZURE_INGEST_COSMOS_DB_DATABASE_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --name $AZURE_INGEST_COSMOS_DB_CONTAINER_NAME \
    --partition-key-path /id

# if USE_REQLOG is true, create a database and container for request logs
###
# AZURE_REQLOG_COSMOS_DB_CONTAINER_NAME="responses"
# AZURE_REQLOG_COSMOS_DB_DATABASE_NAME="log"
# USE_REQLOG="true"
###

if [ "$USE_REQLOG" = "true" ]; then
    echo "Creating Cosmos DB database and container for request logs..."
    az cosmosdb sql database create \
        --account-name $AZURE_INGEST_COSMOS_DB_ACCOUNT_NAME \
        --resource-group $AZURE_RESOURCE_GROUP \
        --name $AZURE_REQLOG_COSMOS_DB_DATABASE_NAME

    az cosmosdb sql container create \
        --account-name $AZURE_INGEST_COSMOS_DB_ACCOUNT_NAME \
        --database-name $AZURE_REQLOG_COSMOS_DB_DATABASE_NAME \
        --resource-group $AZURE_RESOURCE_GROUP \
        --name $AZURE_REQLOG_COSMOS_DB_CONTAINER_NAME \
        --partition-key-path /id
fi

# adding backend app service mi to have cosmos db role
export BACKEND_APP_SERVICE_NAME=$(az webapp list --query "[?contains(name, 'backend')].name" -o tsv)
BACKEND_MI_ID=$(az webapp identity assign --name $BACKEND_APP_SERVICE_NAME --resource-group $AZURE_RESOURCE_GROUP --query principalId -o tsv)

COSMOS_DB_ACCOUNT_ID=$(az cosmosdb show --name $AZURE_INGEST_COSMOS_DB_ACCOUNT_NAME --resource-group $AZURE_RESOURCE_GROUP --query id --output tsv)
echo "Assigning Cosmos DB Data Reader and Cosmos DB Operator permissions to the managed identity..."
# Assign Cosmos DB Data Reader and Cosmos DB Operator permissions to the managed identity
az cosmosdb sql role assignment create --resource-group $AZURE_RESOURCE_GROUP --account-name $AZURE_INGEST_COSMOS_DB_ACCOUNT_NAME --role-definition-id 00000000-0000-0000-0000-000000000002 --principal-id $BACKEND_MI_ID --scope $COSMOS_DB_ACCOUNT_ID


echo "Creating private endpoint for Cosmos DB..."
# Create a private endpoint for the Cosmos DB
COSMOS_DB_ACCOUNT_ID=$(az cosmosdb show --name $AZURE_INGEST_COSMOS_DB_ACCOUNT_NAME --resource-group $AZURE_RESOURCE_GROUP --query id --output tsv)
az network private-endpoint create \
    --name cosmosDbPrivateEndpoint \
    --resource-group $AZURE_RESOURCE_GROUP \
    --vnet-name $AZURE_VNET_NAME \
    --subnet $AZURE_BACKEND_SUBNET_ID \
    --private-connection-resource-id $COSMOS_DB_ACCOUNT_ID \
    --group-id Sql \
    --connection-name cosmosDbPrivateConnection

echo "Creating Private DNS Zone for Cosmos DB..."
# Create a Private DNS Zone for Cosmos DB
DNS_ZONE_NAME=privatelink.documents.azure.com
az network private-dns zone create --resource-group $AZURE_RESOURCE_GROUP --name $DNS_ZONE_NAME

echo "Linking Private DNS Zone to VNet..."
# Link the Private DNS Zone to the VNet
az network private-dns link vnet create \
    --resource-group $AZURE_RESOURCE_GROUP \
    --zone-name $DNS_ZONE_NAME \
    --name myDNSLink \
    --virtual-network $AZURE_VNET_NAME \
    --registration-enabled false

# Configure DNS settings on the private endpoint
az network private-endpoint dns-zone-group create \
    --resource-group $AZURE_RESOURCE_GROUP \
    --endpoint-name cosmosDbPrivateEndpoint \
    --name cosmosDbPrivateDnsZoneGroup \
    --private-dns-zone $DNS_ZONE_NAME \
    --zone-name $DNS_ZONE_NAME


echo "Logging in to ACR..."
# Log in to the ACR
az acr login --name $AZURE_INGEST_ACR_NAME

echo "PUSHING IMAGE TO ACR"
docker build . -t $AZURE_INGEST_ACR_NAME.azurecr.io/$AZURE_INGEST_IMAGE_NAME:latest -f $AZURE_INGEST_DOCKERFILE_PATH
docker push $AZURE_INGEST_ACR_NAME.azurecr.io/$AZURE_INGEST_IMAGE_NAME:latest

# echo "Building Docker image and pushing to ACR..."
# # Build the Docker image and push it to the ACR
# az acr build . --registry $AZURE_INGEST_ACR_NAME --image $IMAGE_NAME:latest -f $AZURE_INGEST_DOCKERFILE_PATH

echo "Creating user-assigned managed identity..."
# Create a user-assigned managed identity
MANAGED_IDENTITY_ID=$(az identity create --resource-group $AZURE_RESOURCE_GROUP --name $AZURE_INGEST_ACA_MI_NAME --query id --output tsv)
MANAGED_IDENTITY_OBJECT_ID=$(az identity show --resource-group $AZURE_RESOURCE_GROUP --name $AZURE_INGEST_ACA_MI_NAME --query principalId --output tsv)
MANAGED_IDENTITY_CLIENT_ID=$(az identity show --resource-group $AZURE_RESOURCE_GROUP --name $AZURE_INGEST_ACA_MI_NAME --query clientId --output tsv)


echo "Assigning ACR pull permissions to the managed identity..."
# Assign ACR pull permissions to the managed identity
ACR_ID=$(az acr show --name $AZURE_INGEST_ACR_NAME --resource-group $AZURE_RESOURCE_GROUP --query id --output tsv)

az role assignment create --assignee $MANAGED_IDENTITY_OBJECT_ID --role "AcrPull" --scope $ACR_ID

echo "Assigning Storage Blob Data Reader and Storage Queue Data Message Reader permissions to the managed identity..."
# Assign Storage Blob Data Reader and Storage Queue Data Message Reader permissions to the managed identity
STORAGE_ACCOUNT_ID=$(az storage account show --name $AZURE_STORAGE_ACCOUNT --resource-group $AZURE_RESOURCE_GROUP --query id --output tsv)
az role assignment create --assignee $MANAGED_IDENTITY_OBJECT_ID --role "Storage Blob Data Reader" --scope $STORAGE_ACCOUNT_ID
az role assignment create --assignee $MANAGED_IDENTITY_OBJECT_ID --role "Storage Queue Data Contributor" --scope $STORAGE_ACCOUNT_ID

COSMOS_DB_ACCOUNT_ID=$(az cosmosdb show --name $AZURE_INGEST_COSMOS_DB_ACCOUNT_NAME --resource-group $AZURE_RESOURCE_GROUP --query id --output tsv)

echo "Assigning Cosmos DB Data Reader and Cosmos DB Operator permissions to the managed identity..."
# Assign Cosmos DB Data Reader and Cosmos DB Operator permissions to the managed identity
az cosmosdb sql role assignment create --resource-group $AZURE_RESOURCE_GROUP --account-name $AZURE_INGEST_COSMOS_DB_ACCOUNT_NAME --role-definition-id 00000000-0000-0000-0000-000000000002 --principal-id $MANAGED_IDENTITY_OBJECT_ID --scope $COSMOS_DB_ACCOUNT_ID

echo "Assigning additional roles to the managed identity at the subscription scope..."
# Assign additional roles to the managed identity at the subscription scope
az role assignment create --assignee $MANAGED_IDENTITY_OBJECT_ID --role "Search Index Data Contributor" --scope /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP
az role assignment create --assignee $MANAGED_IDENTITY_OBJECT_ID --role "Cognitive Services OpenAI Contributor" --scope /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$AZURE_OPENAI_RESOURCE_GROUP
az role assignment create --assignee $MANAGED_IDENTITY_OBJECT_ID --role "Search Index Data Reader" --scope /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP
az role assignment create --assignee $MANAGED_IDENTITY_OBJECT_ID --role "Cognitive Services Data Contributor (Preview)" --scope /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP
az role assignment create --assignee $MANAGED_IDENTITY_OBJECT_ID --role "Search Service Contributor" --scope /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP

# Create a container app environment

# update aca subnet with Microsoft.App/environments delegation
az network vnet subnet update --name $AZURE_INGEST_CONTAINER_APP_SUBNET_NAME --vnet-name $AZURE_VNET_NAME --resource-group $AZURE_RESOURCE_GROUP --delegations "Microsoft.App/environments"

az containerapp env create \
    --enable-workload-profiles \
    --resource-group $AZURE_RESOURCE_GROUP \
    --name $AZURE_INGEST_ACA_ENVIRONMENT_NAME \
    --location $AZURE_LOCATION \
    --infrastructure-subnet-resource-id $AZURE_ACA_SUBNET_ID \
    --internal-only true

echo "Deploying container app job..."
# Deploy a container app job that is scaled by a storage queue
az containerapp job create \
    --name ingest-job \
    --resource-group $AZURE_RESOURCE_GROUP \
    --image $AZURE_INGEST_ACR_NAME.azurecr.io/$AZURE_INGEST_IMAGE_NAME:latest \
    --registry-identity $MANAGED_IDENTITY_ID \
    --registry-server $AZURE_INGEST_ACR_NAME.azurecr.io \
    --environment $AZURE_INGEST_ACA_ENVIRONMENT_NAME \
    --cpu 0.5 \
    --memory 1.0Gi \
    --trigger-type Event \
    --max-executions 10 \
    --env-vars "AZURE_STORAGE_ACCOUNT_URL=$AZURE_STORAGE_ACCOUNT.queue.core.windows.net" "AZURE_STORAGE_QUEUE_NAME=$AZURE_INGEST_QUEUE_NAME" "AZURE_STORAGE_DEADLETTER_QUEUE_NAME=$AZURE_INGEST_DEADLETTER_QUEUE_NAME" "CLOUD_ENVIRONMENT=Azure" "AZURE_CLIENT_ID=$MANAGED_IDENTITY_CLIENT_ID" "AZURE_STORAGE_ACCOUNT_KB_NAME=$AZURE_STORAGE_ACCOUNT" "AZURE_STORAGE_CONTAINER_KB_NAME=$AZURE_INGEST_STG_CONTAINER_NAME" "COSMOS_DB_ACCOUNT_URL=https://$AZURE_INGEST_COSMOS_DB_ACCOUNT_NAME.documents.azure.com:443/" "COSMOS_DB_ACCOUNT_NAME=$AZURE_INGEST_COSMOS_DB_ACCOUNT_NAME" "COSMOS_DB_DATABASE_NAME=$AZURE_INGEST_COSMOS_DB_DATABASE_NAME" "COSMOS_DB_CONTAINER_NAME=$AZURE_INGEST_COSMOS_DB_CONTAINER_NAME" \
    --mi-user-assigned $MANAGED_IDENTITY_ID \
    --scale-rule-name azure-queue \
    --scale-rule-type azure-queue \
    --scale-rule-identity $MANAGED_IDENTITY_ID \
    --scale-rule-metadata "accountName=$AZURE_STORAGE_ACCOUNT" "queueName=$AZURE_INGEST_QUEUE_NAME" "queueLength=10" "queueLengthStrategy=visibleonly" \
    --polling-interval 30

echo "Deployment completed."
