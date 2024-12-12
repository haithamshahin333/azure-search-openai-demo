#!/bin/bash

az extension add -n containerapp

# Variables
### SET ENV VARS from .env.local

echo "Creating Azure Container Registry (ACR)..."
# Create an Azure Container Registry (ACR)
az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Basic --location $LOCATION

echo "Logging in to ACR..."
# Log in to the ACR
az acr login --name $ACR_NAME

echo "Building Docker image and pushing to ACR..."
# Build the Docker image and push it to the ACR
az acr build . --registry $ACR_NAME --image $IMAGE_NAME:latest -f $DOCKERFILE_PATH

echo "Creating user-assigned managed identity..."
# Create a user-assigned managed identity
MANAGED_IDENTITY_ID=$(az identity create --resource-group $RESOURCE_GROUP --name $MANAGED_IDENTITY_NAME --query id --output tsv)
MANAGED_IDENTITY_OBJECT_ID=$(az identity show --resource-group $RESOURCE_GROUP --name $MANAGED_IDENTITY_NAME --query principalId --output tsv)

echo "Assigning ACR pull permissions to the managed identity..."
# Assign ACR pull permissions to the managed identity
ACR_ID=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query id --output tsv)

az role assignment create --assignee $MANAGED_IDENTITY_OBJECT_ID --role "AcrPull" --scope $ACR_ID

echo "Assigning Storage Blob Data Reader and Storage Queue Data Message Reader permissions to the managed identity..."
# Assign Storage Blob Data Reader and Storage Queue Data Message Reader permissions to the managed identity
STORAGE_ACCOUNT_ID=$(az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $RESOURCE_GROUP --query id --output tsv)
az role assignment create --assignee $MANAGED_IDENTITY_OBJECT_ID --role "Storage Blob Data Reader" --scope $STORAGE_ACCOUNT_ID
az role assignment create --assignee $MANAGED_IDENTITY_OBJECT_ID --role "Storage Queue Data Contributor" --scope $STORAGE_ACCOUNT_ID

echo "Assigning additional roles to the managed identity at the subscription scope..."
# Assign additional roles to the managed identity at the subscription scope
az role assignment create --assignee $MANAGED_IDENTITY_OBJECT_ID --role "Search Index Data Contributor" --scope /subscriptions/$SUBSCRIPTION_ID
az role assignment create --assignee $MANAGED_IDENTITY_OBJECT_ID --role "Cognitive Services OpenAI Contributor" --scope /subscriptions/$SUBSCRIPTION_ID
az role assignment create --assignee $MANAGED_IDENTITY_OBJECT_ID --role "Search Index Data Reader" --scope /subscriptions/$SUBSCRIPTION_ID

# Create a container app environment
az containerapp env create --name $ENVIRONMENT --resource-group $RESOURCE_GROUP --location $LOCATION

echo "Deploying container app job..."
# Deploy a container app job that is scaled by a storage queue
az containerapp job create \
    --name $CONTAINER_APP_JOB_NAME \
    --resource-group $RESOURCE_GROUP \
    --image $ACR_NAME.azurecr.io/$IMAGE_NAME:latest \
    --registry-identity $MANAGED_IDENTITY_ID \
    --registry-server $ACR_NAME.azurecr.io \
    --environment $ENVIRONMENT \
    --cpu 0.5 \
    --memory 1.0Gi \
    --trigger-type Event \
    --max-executions 5 \
    --env-vars "AZURE_STORAGE_ACCOUNT_URL=$STORAGE_ACCOUNT_NAME.queue.core.windows.net" "AZURE_STORAGE_QUEUE_NAME=$QUEUE_NAME" "AZURE_STORAGE_DEADLETTER_QUEUE_NAME=$DEADLETTER_QUEUE_NAME" "CLOUD_ENVIRONMENT=Azure" \
    --mi-user-assigned $MANAGED_IDENTITY_ID \
    --scale-rule-name azure-queue \
    --scale-rule-type azure-queue \
    --scale-rule-identity $MANAGED_IDENTITY_ID \
    --scale-rule-metadata "accountName=$STORAGE_ACCOUNT_NAME" "queueName=$QUEUE_NAME" "queueLength=10" "queueLengthStrategy=visibleonly" \
    --polling-interval 30

echo "Deployment completed."