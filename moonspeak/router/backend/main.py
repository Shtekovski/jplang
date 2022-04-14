#!/usr/bin/env python3
import os
import json
import sqlite3
import re
import uuid
from urllib.parse import urlparse

from fastapi import FastAPI
from fastapi.requests import Request
from fastapi.responses import Response, FileResponse, RedirectResponse
import uvicorn
import requests

VERSION = "0.1"
DB_PATH = "../tmp/hud_features.db"
DB = sqlite3.connect(DB_PATH)
MAPPING = {}

app = FastAPI()


@app.api_route("/api/routing/{fid}/{furl:path}", methods=["GET", "HEAD", "POST", "PATCH", "PUT", "DELETE", "OPTIONS"])
async def routing(request: Request, fid, furl: str):
    print(f'Request {furl} of feature {fid}')
    feature_root_url = MAPPING[fid]
    url = feature_root_url + furl
    r = requests.request(request.method, url, headers=request.headers, data=await request.body())
    print(f'Requested {r.url}')
    if not furl:
        # modify returned content if we were requesting root doc, delete content-lenght so it will get recalculated
        new_content = modify_root_doc(r.text, fid)
        del r.headers["content-length"]
        return Response(content=new_content, status_code=r.status_code, headers=r.headers)
    return Response(content=r.content, status_code=r.status_code, headers=r.headers)


@app.get("/")
def index():
    return static("index.html")


@app.get("/static/{path:path}")
def static(path):
    if "index.html" in path:
        p = os.path.join("..", "frontend", path)
    else:
        p = os.path.join("..", "frontend", "static", path)

    if os.path.exists(p):
        return FileResponse(p)
    else:
        return Response(status_code=404)


def modify_root_doc(doc_text, fid):
    from bs4 import BeautifulSoup
    soup = BeautifulSoup(doc_text, 'html.parser')
    base_tag = soup.new_tag("base", href="http://localhost:9000/api/routing/{}/".format(fid))
    soup.head.insert(0, base_tag)
    return str(soup)


# def get_modified_root_doc(fid, feature_root_url):
#     r = requests.get(feature_root_url)
# 
#     from bs4 import BeautifulSoup
#     soup = BeautifulSoup(r.text, 'html.parser')
# 
#     base_tag = soup.new_tag("base", href="http://localhost:9000/api/routing/{}/".format(fid))
#     soup.head.insert(0, base_tag)
# 
#     resp = {
#         "text": str(soup),
#         "soup": soup,
#     }
#     return resp


@app.get("/api/getfeature")
def feature(feature_url: str):
    # add mapping with unified url representation
    fid = str(uuid.uuid4())
    MAPPING[fid] = urlparse(feature_url).geturl()

    # return root URL for this feature
    return { 
        "src" : "http://localhost:9000/api/routing/{}/".format(fid),
        "text" : "use src",
    }


def db_init():
    c = DB.cursor()
    c.execute("""CREATE TABLE hud_features (
            id TEXT NOT NULL UNIQUE
            , url TEXT NOT NULL UNIQUE
            , notes TEXT
            , PRIMARY KEY (id, url)
        );
        """)
    DB.commit()


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description='Run as "python main.py"')
    parser.add_argument('port', type=int, help='port number')
    args = parser.parse_args()

    db_needs_init = (not os.path.isfile(DB_PATH)) or (
        os.path.getsize(DB_PATH) == 0)

    if db_needs_init:
        db_init()

    if not db_needs_init:
        # if db already existed, read some data from it
        c = DB.cursor()
        c.execute("SELECT * FROM hud_features")
        rows = c.fetchall()
        for r in rows:
            name, url, notes = r
            print(r)

    print("Running server on port {}".format(args.port))
    import logging
    uvicorn.run(app, host="0.0.0.0", port=args.port, debug=True)