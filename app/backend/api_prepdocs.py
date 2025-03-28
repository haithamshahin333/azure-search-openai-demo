from fastapi import FastAPI
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import argparse
import asyncio
import logging
from dotenv import load_dotenv
from azure.monitor.opentelemetry import configure_azure_monitor
from opentelemetry.instrumentation.openai import OpenAIInstrumentor
import uuid
import os
from azure.cosmos import CosmosClient, exceptions
from azure.identity import DefaultAzureCredential  # new import

from opentelemetry import trace

configure_azure_monitor(
    logger_name="api_prepdocs"
)

OpenAIInstrumentor().instrument()

# Import the process_documents function from prepdocs.py
from prepdocs import process_documents

app = FastAPI()
logger = logging.getLogger("scripts")
logger.setLevel(logging.DEBUG)

# Initialize Cosmos DB client using provided environment variables
cosmos_endpoint = os.getenv("AZURE_COSMOS_ENDPOINT")
# Remove cosmos_key variable and use credential instead
credential = DefaultAzureCredential()
cosmos_database = os.getenv("AZURE_COSMOS_DATABASE")
cosmos_container_name = os.getenv("AZURE_COSMOS_OPERATIONS_CONTAINER")
client = CosmosClient(cosmos_endpoint, credential=credential)
db = client.get_database_client(cosmos_database)
container = db.get_container_client(cosmos_container_name)

class DocumentProcessRequest(BaseModel):
    bloburl: str
    action: str
    category: str | None = None

async def process_wrapper(args, op_id):
    try:
        await process_documents(args)
        # Update cosmos doc status to succeeded
        doc = container.read_item(item=op_id, partition_key=op_id)
        doc["status"] = "succeeded"
        container.upsert_item(doc)
    except Exception as e:
        # Update cosmos doc status to failed with error message
        doc = container.read_item(item=op_id, partition_key=op_id)
        doc["status"] = "failed"
        doc["error"] = str(e)
        container.upsert_item(doc)

@app.post("/api/process-documents")
async def api_process_documents(doc_request: DocumentProcessRequest):
    """
    Receives a JSON payload containing:
    {
      "bloburl": "<URL of blob>",
      "action": "add" or "remove" or "removeall",
      "category": "<Optional category>"
    }
    Then calls process_documents to handle it.
    """
    tracer = trace.get_tracer(__name__)

    bloburl = doc_request.bloburl
    action = doc_request.action.lower()
    category = doc_request.category

    # Validate presence of bloburl
    if not bloburl:
        return JSONResponse(
            status_code=400,
            content={"error": "Missing 'bloburl' in request body"}
        )

    # Map action to argparse flags
    remove = action == "remove"
    removeall = action == "removeall"

    # Construct argparse namespace
    args = argparse.Namespace(
        bloburl=bloburl,
        remove=remove,
        removeall=removeall,
        files=None,
        category=category,
        skipblobs=False,
        disablebatchvectors=False,
        searchkey=None,
        storagekey=None,
        datalakekey=None,
        documentintelligencekey=None,
        searchserviceassignedid=None,
        verbose=True
    )

    op_id = str(uuid.uuid4())
    # Create initial operation document in Cosmos DB with passed arguments and initial status
    initial_doc = {
        "id": op_id,
        "operationid": op_id,
        "status": "queued",
        "args": vars(args)
    }
    container.create_item(initial_doc)

    with tracer.start_as_current_span("api_process_documents") as span:
        span.set_attribute("api_prepdocs.bloburl", bloburl)
        span.set_attribute("api_prepdocs.action", action)
        if category:
            span.set_attribute("api_prepdocs.category", category)
        try:
            asyncio.create_task(process_wrapper(args, op_id))
            return JSONResponse(
                status_code=202,
                content={
                    "status": "accepted",
                    "bloburl": bloburl,
                    "action": action,
                    "location": f"/api/process-documents/status/{op_id}"
                }
            )
        except Exception as e:
            logger.error(f"Error queuing document processing: {e}")
            return JSONResponse(
                status_code=500,
                content={"error": str(e)}
            )

@app.get("/api/process-documents/status/{operationid}")
async def get_status(operationid: str):
    try:
        doc = container.read_item(item=operationid, partition_key=operationid)
        return JSONResponse(
            status_code=200,
            content={"operationid": operationid, "status": doc}
        )
    except exceptions.CosmosResourceNotFoundError:
        return JSONResponse(
            status_code=404,
            content={"error": "Operation ID not found"}
        )