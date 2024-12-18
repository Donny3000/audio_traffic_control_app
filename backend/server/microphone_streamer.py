import time
import threading
import logging
import numpy   as np
import pyaudio as pa

from pathlib        import Path
from configparser   import ConfigParser
from collections    import deque
from flask_socketio import SocketIO


class MicrophoneStreamer(object):
    def __init__(self, sio: SocketIO, config_file: Path, retries: int=3, retry_delay: int=2):
        self._config = ConfigParser()
        with open(config_file) as f:
            self._config.read_file(f)

        self._sio              = sio
        self._retries          = retries
        self._retry_delay      = retry_delay

        # PyAudio Configuration
        self._p                = pa.PyAudio()
        mic                    = self._p.get_default_input_device_info()
        self.sample_rate       = self._config.getint('Audio', 'SampleRate', fallback=int(mic['defaultSampleRate']))
        self.window_size       = self._config.getint('Audio', 'WindowSize', fallback=2048)
        self._num_channels     = mic['maxInputChannels']
        self._dev_idx          = mic['index']
        self._streaming        = False
        self._in_stream        = None
        self.thread            = None

        # Audio Processing Configuration
        self._avg_buffer       = deque(maxlen=self._config.getint('Audio', 'FilterSize'))
        self._last_update_time = time.time()
        self._stream_fps       = self._config.getfloat('Audio', 'StreamFps')
        self._stream_period    = 1 / self._stream_fps

        self._logger           = logging.getLogger('MicrophoneStreamer')

    def cleanup(self):
        if self._in_stream is not None:
            if not self._in_stream.is_stopped():
                self._in_stream.stop_stream()
            self._in_stream.close()
        self._p.terminate()
        self._logger.info("PyAudio terminated.")
    
    def process_audio(self, samples: np.ndarray):
        curr_time = time.time()
        time_delta = curr_time - self._last_update_time
        if ((time_delta > self._stream_period) and
            (samples is not None)):
            self._last_update_time = curr_time
            win_size               = samples.shape[-1]
            real_win_size          = int(win_size / 2)
            sp                     = np.absolute(np.fft.fft(samples)[1:real_win_size])
            self._avg_buffer.appendleft(20 * np.log10(2 * np.abs(sp) / real_win_size))
            mags                   = np.mean(self._avg_buffer, axis=0)
            freqs                  = self.sample_rate * np.fft.fftfreq(win_size)[1:real_win_size]

            # Emit audio data to the frontend
            #samples_out = np.uint8(samples / 32768.0)
            self._sio.emit(
                self._config['Channels']['Samples'],
                {
                    'freqs':   freqs.tolist(),
                    'mags':    mags.tolist(),
                    'samples': samples.tolist()
                }
                #namespace=self._config['Namespaces']['Client'],
            )
            # print(f"Max Freq: {freqs[mags.argmax()]} @ {mags.max()} dB")
    
    def _stream_audio(self):
        """Handles the audio streaming in a separate thread with retries."""
        attempt = 0
        while attempt < self._retries and self._streaming:
            try:
                self._in_stream = self._p.open(
                    format=pa.paInt16,
                    channels=self._num_channels,
                    rate=self.sample_rate,
                    input=True,
                    input_device_index=self._dev_idx,
                    frames_per_buffer=self.window_size,
                )

                self._logger.info(f"Audio stream started successfully on attempt {attempt + 1}.")
                self._logger.info(f"Sample Rate: {self.sample_rate} | Buffer Size: {self.window_size}")
                self._logger.info(f"Stream FPS: {self._stream_fps} fps | Stream Period: {self._stream_period:03f}")

                self._throttle_cnt = 0

                while self._streaming:
                    try:
                        # Read audio data from the microphone
                        audio_data = np.frombuffer(
                            self._in_stream.read(self.window_size, exception_on_overflow=False),
                            dtype=np.int16
                        )
                        self.process_audio(audio_data)
                    except Exception as e:
                        self._logger.error(f"Error reading or emitting audio data: {e}")
                        break
                    
                break  # Exit retry loop if the stream was successfully opened

            except Exception as e:
                attempt += 1
                self._logger.error(f"Failed to start audio stream on attempt {attempt}: {e}")
                if attempt < self.retries:
                    self._logger.info(f"Retrying in {self._retry_delay} seconds...")
                    time.sleep(self._retry_delay)
                else:
                    self._logger.error("Max retries reached. Unable to start audio stream.")
                    self._sio.emit('audio_error', {'error': f"Unable to start audio stream after {self._retries} retries."})
                    self.streaming = False

        # Ensure the stream is closed if stopped
        if self._in_stream is not None:
            self._in_stream.stop_stream()
            self._in_stream.close()
            self._in_stream = None
            self._logger.info("Audio stream closed.")
    
    def start_stream(self):
        if not self._streaming:
            if self.thread is None:
                self._streaming = True
                self.thread = threading.Thread(target=self._stream_audio)
                self.thread.start()
            else:
                self.stop_stream()
        else:
            print("[INFO] Recording already in progress")

    def stop_stream(self):
        if self._streaming:
            self._streaming = False
            if self.thread:
                self.thread.join()
                self.thread = None
        else:
            print("[INFO] Recording not in progress")
