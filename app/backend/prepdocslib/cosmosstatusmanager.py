import datetime
import logging
from typing import Any, Dict, List, Union

from azure.cosmos.aio import CosmosClient
from azure.core.credentials_async import AsyncTokenCredential
from azure.cosmos.exceptions import CosmosResourceExistsError, CosmosHttpResponseError

logger = logging.getLogger("scripts")

class CosmosStatusManager:
    def __init__(self, cosmos_endpoint: str, cosmos_credential: Union[AsyncTokenCredential, str], database_name: str, container_name: str):
        self.cosmos_endpoint = cosmos_endpoint
        self.cosmos_credential = cosmos_credential
        self.database_name = database_name
        self.container_name = container_name

    async def log_file_indexed(self, file_id: str, chunk_ids: List[str], filename: str,
                               sourcefile: str, category: str, pages: int):
        logger.info("Logging file indexed: %s", sourcefile)
        async with CosmosClient(self.cosmos_endpoint, credential=self.cosmos_credential) as client:
            db = client.get_database_client(self.database_name)
            container = db.get_container_client(self.container_name)
            now_utc = datetime.datetime.now(datetime.timezone.utc).isoformat()

            # first check if the document already exists and update the columns as necessary
            try:
                doc = await container.read_item(file_id, partition_key=file_id)
                logger.info("Cosmos status: File '%s' found, updating status.", filename)
                doc["CURRENT_STATUS"] = "INDEXED"
                doc["LAST_MODIFIED"] = now_utc
                if "INDEX_HISTORY" not in doc:
                    doc["INDEX_HISTORY"] = []
                doc["INDEX_HISTORY"].append({"ACTION": "INDEXED", "TIMESTAMP": now_utc})
                # update the chunk ids
                doc["CHUNK_IDS"] = chunk_ids
                # update the pages
                doc["PAGES"] = pages
                # update the filename
                doc["FILENAME"] = filename
                # update the sourcefile
                doc["SOURCEFILE"] = sourcefile
                await container.replace_item(doc, doc)
                logger.info("Cosmos status updated: File '%s' indexed.", filename)
                return
            except CosmosHttpResponseError as e:
                if e.status_code != 404:
                    logger.error("Error reading file status from Cosmos: %s", e)
                    return
                logger.info("Cosmos status: File '%s' not found, creating new entry.", filename)

            # if the document does not exist, create a new one
            doc = {
                "id": file_id,
                "CURRENT_STATUS": "INDEXED",
                "FILENAME": filename,
                "SOURCEFILE": sourcefile,
                "CATEGORY": category,
                "PAGES": pages,
                "CHUNK_IDS": chunk_ids,
                "LAST_MODIFIED": now_utc,
                "INDEX_HISTORY": [{"ACTION": "INDEXED", "TIMESTAMP": now_utc}]
            }
            try:
                await container.create_item(doc)
                logger.info("Cosmos status created: File '%s' indexed.", filename)
            except CosmosResourceExistsError:
                logger.error("Error creating file status in Cosmos: Document already exists.")
            except CosmosHttpResponseError as e:
                logger.error("Error creating file status in Cosmos: %s", e)
                return



    async def log_file_removed(self, sourcefile: str):
        # log that the file has been removed from the index by updating the INDEX_HISTORY
        async with CosmosClient(self.cosmos_endpoint, credential=self.cosmos_credential) as client:
            db = client.get_database_client(self.database_name)
            container = db.get_container_client(self.container_name)
            now_utc = datetime.datetime.now(datetime.timezone.utc).isoformat()

            query = "SELECT * FROM c WHERE c.SOURCEFILE = @sourcefile"
            parameters = [{"name": "@sourcefile", "value": sourcefile}]
            items = [item async for item in container.query_items(query=query, parameters=parameters)]

            if len(items) != 1:
                logger.error("Error: Expected one item, but found %d items for sourcefile '%s'", len(items), sourcefile)
                return

            doc = items[0]
            doc["CURRENT_STATUS"] = "REMOVED"
            doc["LAST_MODIFIED"] = now_utc
            doc["INDEX_HISTORY"].append({"ACTION": "REMOVED", "TIMESTAMP": now_utc})
            # update the chunk ids
            doc["CHUNK_IDS"] = []
            # update the pages
            doc["PAGES"] = 0

            try:
                await container.replace_item(doc, doc)
                logger.info("Cosmos status updated: File '%s' removed.", doc["id"])
            except CosmosResourceExistsError:
                logger.error("Error updating file status in Cosmos: Document already exists.")
            except CosmosHttpResponseError as e:
                logger.error("Error updating file status in Cosmos: %s", e)
                return