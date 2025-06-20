import os
from flask import Flask

app = Flask(__name__)
title = os.getenv("APP_TITLE", "Default Title")

@app.route("/")
def hello():
    return f"<h1>{title}</h1><p>Hello from Cloud Run!</p>"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
