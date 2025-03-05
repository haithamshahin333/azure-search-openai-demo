import json
import random
import time
from locust import HttpUser, between, task, events
# from azure.identity import DefaultAzureCredential
import os


TOKEN_RESOURCE = os.getenv("TOKEN_RESOURCE", "")
HOST = os.getenv("HOST", "")
TOKEN = os.getenv("TOKEN","")

class ChatUser(HttpUser):
    host = HOST
    wait_time = between(5, 15)

    def on_start(self):
        if TOKEN:
            self.headers = {"Authorization": f"Bearer {TOKEN}"}
        # else:
        #     credential = DefaultAzureCredential()
        #     token = credential.get_token(TOKEN_RESOURCE)
        #     self.headers = {"Authorization": f"Bearer {token.token}"}

    # @events.request.add_listener
    # def on_request(request_type, name, response_time, response_length, response, context, **kwargs):
    #     if name == "/api/chat/stream":
    #         print(f"Response length is {response_length} from the event")

    @task
    def ask_question(self):
        response = self.client.post(
            "/api/chat/stream",
            headers=self.headers,
            stream=True,
            json={
                "messages": [
                    {
                        "content": random.choice(
                            [
                                f"What is included in my Northwind Health Plus plan that is not in standard? The current time is {time.time()}",
                            ]
                        ),
                        "role": "user",
                    },
                ],
                "context": {
                    "overrides": {
                        "retrieval_mode": "hybrid",
                        "semantic_ranker": True,
                        "semantic_captions": False,
                        "top": 3,
                        "suggest_followup_questions": True,
                    },
                },
            },
        )

        response_stream = []
        for line in response.iter_lines(decode_unicode=True):
            if line:
                response_stream.append(line)
                # print("Streamed Line:", line)

        # Load the initial streamed response into a JSON object
        data = json.loads(response_stream[0])

        # Assume the sourcepage is embedded in one of the data_points text strings.
        # For example, if a data_point is formatted as:
        # "Benefit_Options;semicolon;filename.pdf#page=3:  <content text>"
        data_points = data.get("context", {}).get("data_points", {}).get("text", [])
        if data_points:
            # Extract the sourcepage text (portion before the first colon)
            sourcepage_raw = data_points[0].split(":", 1)[0].strip()
            print("Extracted sourcepage:", sourcepage_raw)

            # Use the extracted value to call /api/content/{sourcepage}
            content_endpoint = f"/api/content/{sourcepage_raw}"
            self.client.get(content_endpoint, headers=self.headers, name="/api/content")
        else:
            print("No data_points with sourcepage found.")