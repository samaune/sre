from fastapi import FastAPI
from fastapi.responses import JSONResponse
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
import os
import json

app = FastAPI()
# Mount the "static" directory under /static
app.mount("/extjs", StaticFiles(directory="node_modules/ui-extjs"), name="extjs")

# Load once at startup
with open("./data/config.json") as f:
    config = json.load(f)

with open("./data/session.json") as f:
    session = json.load(f)

@app.get("/config")
def get_config():
    return JSONResponse(content=config)

@app.get("/session")
def get_session():
    return JSONResponse(content=session)

# Serve index.html at root "/"
@app.get("/")
async def root():
    index_path = os.path.join("public", "index.html")
    return FileResponse(index_path)
# uvicorn api:app --reload --host 0.0.0.0
