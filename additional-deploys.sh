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

