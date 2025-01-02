#!/usr/bin/env python
import os
import db, auth
import logging

from configparser        import ConfigParser
from flask               import Flask, request
from flask_socketio      import SocketIO, emit
from microphone_streamer import MicrophoneStreamer


streaming = False
config    = ConfigParser()
with open('./config.ini') as f:
    config.read_file(f)
app       = Flask("AudioStreamer", instance_relative_config=True)
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
socketio = SocketIO(app, cors_allowed_origins="*")

# Initialize logger
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger('AudioServer')

# Setup the microphone audio streaming
mic_streamer = MicrophoneStreamer(socketio, './config.ini')

# A simple page that says hello
@app.route('/hello')
def hello():
    return "Great! The server-side application is working!"

@socketio.on('start_audio')#, namespace=config['Namespaces']['Client'])
def start_audio(audio_config):
    """Starts the audio streaming."""
    try:
        if audio_config['sample_rate']:
            mic_streamer.sample_rate = audio_config['sample_rate']
        if audio_config['buffer_size']:
            mic_streamer.window_size = audio_config['buffer_size']

        mic_streamer.start_stream()
        emit('audio_response', {'status': 'started'})
    except Exception as e:
        logger.error(f"Error starting audio streaming: {e}")
        emit('audio_error', {'error': str(e)})

@socketio.on('stop_audio')#, namespace=config['Namespaces']['Client'])
def stop_audio():
    """Stops the audio streaming."""
    try:
        mic_streamer.stop_stream()
        emit('audio_response', {'status': 'stopped'})
    except Exception as e:
        logger.error(f"Error stopping audio streaming: {e}")
        emit('audio_error', {'error': str(e)})

@socketio.on('connect')#, namespace=config['Namespaces']['Client'])
def connect_client():
    logger.info(f"Client connected: {request.sid}")


@socketio.on('disconnect')#, namespace=config['Namespaces']['Client'])
def disconnect_client():
    logger.info(f"Client disconnected: {request.sid}")


if __name__ == "__main__":
    logger.info(f"Starting Audio Traffic Control Server at http://{config['Server']['Host']}:{config['Server']['Port']}")
    try:
        socketio.run(
            app=app,
            host=config['Server']['Host'],
            port=config['Server']['Port']
        )
    except Exception as e:
        logger.critical(f"Critical error: {e}")
    finally:
        # Ensure PyAudio resources are cleaned up on exit
        mic_streamer.cleanup()
