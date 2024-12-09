import argparse
import asyncio
import logging
import os
from azure.identity.aio import DefaultAzureCredential
from azure.storage.queue.aio import QueueClient
from prepdocs import process_documents
import base64
import json

# Configure logging
logging.basicConfig(format="%(message)s")
logger = logging.getLogger("scripts")
logger.setLevel(logging.INFO)

async def fetch_and_process_messages(queue_client: QueueClient, deadletter_queue_client: QueueClient):
    logger.info("Fetching messages from the queue...")
    messages = queue_client.receive_messages(max_messages=10, visibility_timeout=300)
    exceptions = []
    successful_bloburls = []
    failed_bloburls = []

    async for message in messages:
        try:
            logger.info(f"Processing message: {message.id}")
            # log the message content
            decoded_message = base64.b64decode(message.content).decode('utf-8')
            event = json.loads(decoded_message)
            bloburl = event['data']['url']
            event_type = event['eventType']
            remove = event_type == "Microsoft.Storage.BlobDeleted"

            logger.info(f"Blob URL: {bloburl}")
            logger.info(f"Event Type: {event_type}")

            args = argparse.Namespace(
                bloburl=bloburl,
                remove=remove,
                files=None,
                category=None,
                skipblobs=False,
                disablebatchvectors=False,
                searchkey=None,
                storagekey=None,
                datalakekey=None,
                documentintelligencekey=None,
                searchserviceassignedid=None,
                verbose=True,
                removeall=False
            )
            await process_documents(args)
            
            logger.info(f"Message processed successfully: {message.id}")
            await queue_client.delete_message(message)
            logger.info(f"Message deleted: {message.id}")
            successful_bloburls.append(bloburl)
        except Exception as e:
            logger.error(f"Failed to process message: {e}")
            deadletter_message = {
                "original_id": message.id,
                "content": message.content,
                "bloburl": bloburl
            }
            await deadletter_queue_client.send_message(base64.b64encode(json.dumps(deadletter_message).encode('utf-8')).decode('utf-8'))
            # log that the message has been written to deadletter and is being deleted from the queue
            logger.error(f"Message sent to deadletter queue: {message.id}")
            await queue_client.delete_message(message)
            logger.error(f"Message deleted: {message.id}")
            failed_bloburls.append((bloburl, str(e)))
            exceptions.append(e)

    if successful_bloburls:
        logger.info(f"Successfully processed blob URLs: {successful_bloburls}")
        
    if failed_bloburls:
        logger.error(f"Failed to process blob URLs: {failed_bloburls}")
        
    if exceptions:
        raise Exception(f"Exceptions occurred during message processing: {exceptions}")
    else:
        logger.info("All messages processed successfully.")

async def main():
    credential = DefaultAzureCredential()
    account_url = os.getenv("AZURE_STORAGE_ACCOUNT_URL")
    queue_name = os.getenv("AZURE_STORAGE_QUEUE_NAME")
    deadletter_queue_name = os.getenv("AZURE_STORAGE_DEADLETTER_QUEUE_NAME")

    async with credential:
        async with QueueClient(account_url=account_url, queue_name=queue_name, credential=credential) as queue_client, \
                   QueueClient(account_url=account_url, queue_name=deadletter_queue_name, credential=credential) as deadletter_queue_client:

            logger.info("Starting to fetch and process messages...")
            await fetch_and_process_messages(queue_client, deadletter_queue_client)
            logger.info("Finished processing messages.")

if __name__ == "__main__":
    asyncio.run(main())