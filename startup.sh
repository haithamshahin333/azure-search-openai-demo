#!/bin/bash

echo 'Running "Process Documents"'

echo "Logging in to Azure"
echo "CLOUD_ENVIRONMENT: $CLOUD_ENVIRONMENT"
if [ -z "$CLOUD_ENVIRONMENT" ] || [ "$CLOUD_ENVIRONMENT" == "local" ]; then
  echo "Local Cloud Environment: Logging in to Azure with device code"
  azd auth login --use-device-code
else
  echo "Azure Cloud Environment: Logging in to Azure with identity"
  azd auth login --managed-identity --client-id $AZURE_CLIENT_ID
fi

additionalArgs=""
if [ $# -gt 0 ]; then
  additionalArgs="$@"
fi


# Run the prepdocs.py script with the data path and additional arguments
# echo 'Running "prepdocs.py" with additional arguments: ' $additionalArgs
# exec python app/backend/prepdocs.py --verbose $additionalArgs
exec python app/backend/process_documents.py