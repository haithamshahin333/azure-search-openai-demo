echo "SET ENV VARS"

az webapp create --name $APP_NAME --plan $APP_SERVICE_PLAN --resource-group $RG_NAME --runtime NODE:20-lts

echo "build frontend"
rm -rf frontend.zip
rm -rf frontend
cd app/frontend
npm install
npm run build

echo "create zip file for frontend"
cd ../../frontend
zip -r ../frontend.zip ./*
cd ..

echo "deploy zip file to azure web app"
az webapp config appsettings set --resource-group $RG_NAME --name $APP_NAME --settings SCM_DO_BUILD_DURING_DEPLOYMENT=false
echo "update webapp configuration with a new startup command"
az webapp config set --startup-file "pm2 serve /home/site/wwwroot --no-daemon" --name $APP_NAME --resource-group $RG_NAME
echo "deploy frontend to azure web app"
az webapp deploy --src-path frontend.zip --name $APP_NAME --resource-group $RG_NAME --verbose

echo "validate that allowed_cors on the backend is not set"
echo "CREATE APP REGISTRATIONS"
echo "SET HTTP SETTINGS ON FRONTEND APP SERVICE"
# az rest --method GET --url '/subscriptions/{SUBSCRIPTION_ID}/resourceGroups/{RESOURCE_GROUP}/providers/Microsoft.Web/sites/{WEBAPP_NAME}/config/authsettingsv2/list?api-version=2020-06-01' > authsettings.json
# az rest --method PUT --url '/subscriptions/{SUBSCRIPTION_ID}/resourceGroups/{RESOURCE_GROUP}/providers/Microsoft.Web/sites/{WEBAPP_NAME}/config/authsettingsv2?api-version=2020-06-01' --body @./authsettings.json

echo "REDEPLOY FRONTEND WITH PROPER AUTH SETTINGS CONFIGURED IN APP"
