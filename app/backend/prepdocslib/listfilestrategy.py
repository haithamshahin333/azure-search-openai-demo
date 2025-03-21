import base64
import hashlib
import logging
import os
import re
import tempfile
from abc import ABC
from glob import glob
from typing import IO, AsyncGenerator, Dict, List, Optional, Union

from azure.core.credentials_async import AsyncTokenCredential
from azure.storage.filedatalake.aio import (
    DataLakeServiceClient,
)

from azure.storage.blob.aio import BlobServiceClient
from urllib.parse import urlparse

logger = logging.getLogger("scripts")

class File:
    """
    Represents a file stored either locally or in a data lake storage account
    This file might contain access control information about which users or groups can access it
    """

    def __init__(self, content: IO, acls: Optional[dict[str, list]] = None, url: Optional[str] = None, blob: Optional[bool] = False, blob_name: Optional[str] = None):
        self.content = content
        self.acls = acls or {}
        self.url = url
        self.blob = blob
        self.blob_name = blob_name

    def filename(self):
        if self.blob_name:
            return self.blob_name
        return os.path.basename(self.content.name)

    def file_extension(self):
        return os.path.splitext(self.content.name)[1]

    def filename_to_id(self):
        raw_filename = self.filename()
        filename_hash = hashlib.sha256(raw_filename.encode("utf-8")).hexdigest()
        acls_hash = ""
        if self.acls:
            acls_hash = hashlib.sha256(str(self.acls).encode("utf-8")).hexdigest()
        return f"file-{filename_hash}"

    def close(self):
        if self.content:
            self.content.close()

        if self.blob_name:
            try:
                temp_file_path = os.path.join(tempfile.gettempdir(), self.blob_name)
                if os.path.exists(temp_file_path):
                    logger.info(f"Deleting blob file at {temp_file_path}")
                    os.remove(temp_file_path)
            except Exception as e:
                logger.error(f"Error deleting blob file {self.blob_name}: {e}")


class ListFileStrategy(ABC):
    """
    Abstract strategy for listing files that are located somewhere. For example, on a local computer or remotely in a storage account
    """

    async def list(self) -> AsyncGenerator[File, None]:
        if False:  # pragma: no cover - this is necessary for mypy to type check
            yield

    async def list_paths(self) -> AsyncGenerator[str, None]:
        if False:  # pragma: no cover - this is necessary for mypy to type check
            yield

class BlobListFileStrategy(ListFileStrategy):
    """
    Concrete strategy for listing a single file that is located in a blob storage account
    """

    def __init__(
        self,
        blob_url: str,
        storage_account: str,
        storage_container: str,
        credential: Union[AsyncTokenCredential, str],
    ):
        self.storage_account = storage_account
        self.storage_container = storage_container
        self.blob_url = blob_url
        self.credential = credential

    async def list_paths(self) -> AsyncGenerator[str, None]:
        yield self.extract_blob_name()

    def extract_blob_name(self):
        prefix = f"https://{self.storage_account}.blob.core.windows.net/{self.storage_container}/"
        if self.blob_url.startswith(prefix):
            blob_name = self.blob_url[len(prefix):]
        else:
            raise ValueError("The blob URL does not match the expected pattern.")
        
        return blob_name

    async def list(self) -> AsyncGenerator[File, None]:
        blob_service_client = BlobServiceClient(account_url=f"https://{self.storage_account}.blob.core.windows.net", credential=self.credential)
        container_name = self.storage_container
        blob_name = self.extract_blob_name()

        async with blob_service_client:  # Ensure BlobServiceClient is properly closed
            async with blob_service_client.get_container_client(container_name) as container_client:  # Ensure ContainerClient is properly closed
                temp_file_path = os.path.join(tempfile.gettempdir(), blob_name)
                temp_dir = os.path.dirname(temp_file_path)
                os.makedirs(temp_dir, exist_ok=True)  # Create the directory if it does not exist
                logger.info(f"Downloading {blob_name} to {temp_file_path}")
                try:
                    async with container_client.get_blob_client(blob_name) as blob_client:  # Ensure BlobClient is properly closed
                        with open(temp_file_path, "wb") as temp_file:
                            downloader = await blob_client.download_blob()
                            await downloader.readinto(temp_file)
                    yield File(content=open(temp_file_path, "rb"), url=blob_client.url, blob=True, blob_name=blob_name)
                except Exception as blob_exception:
                    logger.error(f"\tGot an error while reading {blob_name} -> {blob_exception} --> skipping file")
                    try:
                        os.remove(temp_file_path)
                    except Exception as file_delete_exception:
                        logger.error(f"\tGot an error while deleting {temp_file_path} -> {file_delete_exception}")
                    raise


class LocalListFileStrategy(ListFileStrategy):
    """
    Concrete strategy for listing files that are located in a local filesystem
    """

    def __init__(self, path_pattern: str):
        self.path_pattern = path_pattern

    async def list_paths(self) -> AsyncGenerator[str, None]:
        async for p in self._list_paths(self.path_pattern):
            yield p

    async def _list_paths(self, path_pattern: str) -> AsyncGenerator[str, None]:
        for path in glob(path_pattern):
            if os.path.isdir(path):
                async for p in self._list_paths(f"{path}/*"):
                    yield p
            else:
                # Only list files, not directories
                yield path

    async def list(self) -> AsyncGenerator[File, None]:
        async for path in self.list_paths():
            if not self.check_md5(path):
                yield File(content=open(path, mode="rb"))

    def check_md5(self, path: str) -> bool:
        # if filename ends in .md5 skip
        if path.endswith(".md5"):
            return True

        # if there is a file called .md5 in this directory, see if its updated
        stored_hash = None
        with open(path, "rb") as file:
            existing_hash = hashlib.md5(file.read()).hexdigest()
        hash_path = f"{path}.md5"
        if os.path.exists(hash_path):
            with open(hash_path, encoding="utf-8") as md5_f:
                stored_hash = md5_f.read()

        if stored_hash and stored_hash.strip() == existing_hash.strip():
            logger.info("Skipping %s, no changes detected.", path)
            return True

        # Write the hash
        with open(hash_path, "w", encoding="utf-8") as md5_f:
            md5_f.write(existing_hash)

        return False


class ADLSGen2ListFileStrategy(ListFileStrategy):
    """
    Concrete strategy for listing files that are located in a data lake storage account
    """

    def __init__(
        self,
        data_lake_storage_account: str,
        data_lake_filesystem: str,
        data_lake_path: str,
        credential: Union[AsyncTokenCredential, str],
    ):
        self.data_lake_storage_account = data_lake_storage_account
        self.data_lake_filesystem = data_lake_filesystem
        self.data_lake_path = data_lake_path
        self.credential = credential

    async def list_paths(self) -> AsyncGenerator[str, None]:
        async with DataLakeServiceClient(
            account_url=f"https://{self.data_lake_storage_account}.dfs.core.windows.net", credential=self.credential
        ) as service_client, service_client.get_file_system_client(self.data_lake_filesystem) as filesystem_client:
            async for path in filesystem_client.get_paths(path=self.data_lake_path, recursive=True):
                if path.is_directory:
                    continue

                yield path.name

    async def list(self) -> AsyncGenerator[File, None]:
        async with DataLakeServiceClient(
            account_url=f"https://{self.data_lake_storage_account}.dfs.core.windows.net", credential=self.credential
        ) as service_client, service_client.get_file_system_client(self.data_lake_filesystem) as filesystem_client:
            async for path in self.list_paths():
                temp_file_path = os.path.join(tempfile.gettempdir(), os.path.basename(path))
                try:
                    async with filesystem_client.get_file_client(path) as file_client:
                        with open(temp_file_path, "wb") as temp_file:
                            downloader = await file_client.download_file()
                            await downloader.readinto(temp_file)
                    # Parse out user ids and group ids
                    acls: Dict[str, List[str]] = {"oids": [], "groups": []}
                    # https://learn.microsoft.com/python/api/azure-storage-file-datalake/azure.storage.filedatalake.datalakefileclient?view=azure-python#azure-storage-filedatalake-datalakefileclient-get-access-control
                    # Request ACLs as GUIDs
                    access_control = await file_client.get_access_control(upn=False)
                    acl_list = access_control["acl"]
                    # https://learn.microsoft.com/azure/storage/blobs/data-lake-storage-access-control
                    # ACL Format: user::rwx,group::r-x,other::r--,user:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx:r--
                    acl_list = acl_list.split(",")
                    for acl in acl_list:
                        acl_parts: list = acl.split(":")
                        if len(acl_parts) != 3:
                            continue
                        if len(acl_parts[1]) == 0:
                            continue
                        if acl_parts[0] == "user" and "r" in acl_parts[2]:
                            acls["oids"].append(acl_parts[1])
                        if acl_parts[0] == "group" and "r" in acl_parts[2]:
                            acls["groups"].append(acl_parts[1])
                    yield File(content=open(temp_file_path, "rb"), acls=acls, url=file_client.url)
                except Exception as data_lake_exception:
                    logger.error(f"\tGot an error while reading {path} -> {data_lake_exception} --> skipping file")
                    try:
                        os.remove(temp_file_path)
                    except Exception as file_delete_exception:
                        logger.error(f"\tGot an error while deleting {temp_file_path} -> {file_delete_exception}")
