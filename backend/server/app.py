import os
import time
import numpy as np
import db, auth
from configparser import ConfigParser
from flask import Flask, request
from flask_socketio import SocketIO

config = ConfigParser('../config.ini')
app = Flask(__name__, instance_relative_config=True)
app.config.from_mapping(
    SECRET_KEY='dev',
    DATABASE=os.path.sep.join([app.instance_path, 'backend_app.sqlite']),
)

# Ensure the instance folder exists
try:
    os.makedirs(app.instance_path)
except OSError:
    pass

db.init_app(app)
app.register_blueprint(auth.bp)
socketio = SocketIO(app)


# A simple page that says hello
@app.route('/hello')
def hello():
    return "Great! The server-side application is working!"


@socketio.on('connect', namespace=config['Namespaces']['Client'])
def connect_client():
    print(f"[INFO] Client connected: {request.sid}")


@socketio.on('disconnect', namespace=config['Namespaces']['Client'])
def disconnect_client():
    print(f"[INFO] Client disconnected: {request.sid}")


@socketio.on('connect', namespace=config['Namespaces']['Audio'])
def connect_audio():
    print(f"[INFO] Audio Processor connected: {request.sid}")


@socketio.on('disconnect', namespace=config['Namespaces']['Audio'])
def disconnect_audio():
    print(f"[INFO] Audio Processor disconnected: {request.sid}")


@socketio.on(config['Channels']['Samples'])
def handle_audio_message(message):
    socketio.emit(
        config['Channels']['Samples'],
        message,
        namespace=config['Namespaces']['Client']
    )


if __name__ == "__main__":
    print(f"[INFO] Starting Audio Traffic Control Server at http://{config['server']['host']}:{config['server']['port']}")
    socketio.run(app=app, host=config['server']['host'], port=config['server']['port'])
