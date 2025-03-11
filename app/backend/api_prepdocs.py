from fastapi import FastAPI
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import argparse
import asyncio
import logging
from dotenv import load_dotenv
from azure.monitor.opentelemetry import configure_azure_monitor
from opentelemetry.instrumentation.openai import OpenAIInstrumentor

from opentelemetry import trace

configure_azure_monitor(
    logger_name="api_prepdocs"
)

OpenAIInstrumentor().instrument()

# Import the process_documents function from prepdocs.py
from prepdocs import process_documents

app = FastAPI()
logger = logging.getLogger("api_prepdocs")
logger.setLevel(logging.DEBUG)

class DocumentProcessRequest(BaseModel):
    bloburl: str
    action: str
    category: str | None = None

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

    with tracer.start_as_current_span("api_process_documents") as span:
        span.set_attribute("api_prepdocs.bloburl", bloburl)
        span.set_attribute("api_prepdocs.action", action)
        if category:
            span.set_attribute("api_prepdocs.category", category)
        try:
            await process_documents(args)
            return {"status": "success", "bloburl": bloburl, "action": action}
        except Exception as e:
            logger.error(f"Error processing document: {e}")
            return JSONResponse(
                status_code=500,
                content={"error": str(e)}
            )