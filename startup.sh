#!/bin/bash

echo 'Running "prepdocs.py"'

# Use the DATA_PATH environment variable, or default to './data/*' if not set
DATA_PATH=${DATA_PATH:-'./data/*'}


# sleep 1000000

azd auth login --use-device-code

additionalArgs=""
if [ $# -gt 0 ]; then
  additionalArgs="$@"
fi

# Run the prepdocs.py script with the data path and additional arguments
exec python prepdocs.py "$DATA_PATH" --verbose $additionalArgs