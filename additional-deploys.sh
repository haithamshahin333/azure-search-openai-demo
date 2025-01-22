#!/bin/bash

echo "building frontend"
rm -rf frontend.zip
rm -rf frontend
cd app/frontend
npm install
npm run build

echo "create zip file for frontend"
cd ../../frontend
zip -r ../frontend.zip ./*
cd ..

echo "deploy frontend"
az webapp deploy --src-path frontend.zip --name $FRONTEND_APP_SERVICE_NAME --resource-group $AZURE_RESOURCE_GROUP --verbose

echo "validate that allowed_cors on the backend is not set"
echo "CREATE APP REGISTRATIONS"
echo "SET HTTP SETTINGS ON FRONTEND APP SERVICE"
# az rest --method GET --url '/subscriptions/{SUBSCRIPTION_ID}/resourceGroups/{RESOURCE_GROUP}/providers/Microsoft.Web/sites/{WEBAPP_NAME}/config/authsettingsv2/list?api-version=2020-06-01' > authsettings.json
# az rest --method PUT --url '/subscriptions/{SUBSCRIPTION_ID}/resourceGroups/{RESOURCE_GROUP}/providers/Microsoft.Web/sites/{WEBAPP_NAME}/config/authsettingsv2?api-version=2020-06-01' --body @./authsettings.json

echo "REDEPLOY FRONTEND WITH PROPER AUTH SETTINGS CONFIGURED IN APP"

echo "add cosmos role to backend managed identity"
export BACKEND_APP_SERVICE_NAME=$(az webapp list --query "[?contains(name, 'backend')].name" -o tsv)
BACKEND_MI_ID=$(az webapp identity assign --name $BACKEND_APP_SERVICE_NAME --resource-group $AZURE_RESOURCE_GROUP --query principalId -o tsv)

COSMOS_DB_ACCOUNT_ID=$(az cosmosdb show --name $AZURE_INGEST_COSMOS_DB_ACCOUNT_NAME --resource-group $AZURE_RESOURCE_GROUP --query id --output tsv)
echo "Assigning Cosmos DB Data Reader and Cosmos DB Operator permissions to the managed identity..."
# Assign Cosmos DB Data Reader and Cosmos DB Operator permissions to the managed identity
az cosmosdb sql role assignment create --resource-group $AZURE_RESOURCE_GROUP --account-name $AZURE_INGEST_COSMOS_DB_ACCOUNT_NAME --role-definition-id 00000000-0000-0000-0000-000000000002 --principal-id $BACKEND_MI_ID --scope $COSMOS_DB_ACCOUNT_ID
