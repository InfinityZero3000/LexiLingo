import json
import requests
import time
import asyncio
import os
from aiohttp import ClientSession

API_KEY = "AIzaSyA7KgjM3Jt3E09RudKLUcA6e0WO4YOW2vY"
FILE_PATH = "/opt/lexilingo/scripts/categorized_words_final.json"

with open(FILE_PATH, "r", encoding="utf-8") as f:
    data = json.load(f)

missing = [item for item in data if item.get("definition") == "#N/A yet" or not item.get("definition")]
print(f"Found {len(missing)} items missing definitions.")

