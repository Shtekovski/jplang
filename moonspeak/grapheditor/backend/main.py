#!/usr/bin/env python3
import os
import json
import sqlite3
import re

from bottle import response, request, post, get, route, run, template, HTTPResponse, static_file  # type: ignore

VERSION = "0.1"
DB_PATH = "../tmp/kanji-grapheditor.db"
DB = sqlite3.connect(DB_PATH)


@get("/open")
def work():
    c = DB.cursor()
    c.execute("SELECT * FROM diagrams;")
    rows = c.fetchall()
    for r in rows:
        payload = {
            "user_id": r[0],
            "diagram": r[1],
        }
        # just return the first row
        return json.dumps(payload)

    return ""


@post("/save")
def submit():
    payload = request.params

    user_id = "test"
    diagram = payload["xml"]

    try:
        c = DB.cursor()
        # https://www.sqlite.org/lang_replace.html
        # https://www.sqlite.org/lang_UPSERT.html
        c.execute("""INSERT OR ABORT INTO diagrams VALUES (?, ?)
                ON CONFLICT(user_id) DO UPDATE SET diagram=excluded.diagram;
                """,
                  (user_id, diagram))
        DB.commit()
    except Exception as e:
        # return 2xx response because too lazy to unwrap errors in Elm
        return HTTPResponse(status=202, body="{}".format(e))

    # return a fake body because too lazy to unwrap properly in Elm
    return HTTPResponse(status=200, body="")


@get("/")
def index():
    return static("index.html")


@get("/<path:path>")
def static(path):
    if "index.html" in path:
        return static_file("index.html", root="../frontend/")
    return static_file(path, root="../frontend/")


def db_init():
    c = DB.cursor()
    c.execute("""CREATE TABLE diagrams (
            user_id TEXT NOT NULL UNIQUE
            , diagram TEXT NOT NULL UNIQUE
            , PRIMARY KEY (user_id)
        );
        """)
    DB.commit()


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description='Feature, run as "python main.py"')
    parser.add_argument('--port', type=int, default=80, help='port number')
    args = parser.parse_args()

    db_needs_init = (not os.path.isfile(DB_PATH)) or (
        os.path.getsize(DB_PATH) == 0)

    if db_needs_init:
        db_init()

    # other
    print("Running bottle server on port {}".format(args.port))
    run(host="0.0.0.0", port=args.port, debug=True)
