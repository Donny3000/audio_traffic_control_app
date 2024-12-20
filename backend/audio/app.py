#!/usr/bin/env python

import time
import numpy as np
import pyaudio as pa
from configparser import ConfigParser
from collections import deque
import socketio


config = ConfigParser()
with open('../config.ini') as f:
    config.read_file(f)
sio = socketio.Client()


@sio.event
def connect():
    print('[INFO] Successfully connected to server.')


@sio.event
def connect_error(data):
    print(f'[INFO] Failed to connect to server: {data}')


@sio.event
def disconnect():
    print('[INFO] Disconnected from server')


class MicrophoneReader(object):
    def __init__(self):
        self._buffer      = deque(maxlen=config.getint('Audio', 'BufferSize', fallback=1024))
        self._p           = pa.PyAudio()
        mic               = self._p.get_default_input_device_info()
        self._sample_rate = config.getint('Audio', 'SampleRate', fallback=int(mic['defaultSampleRate']))
        self._chunk_size  = config.getint('Audio', 'WindowSize', fallback=2048)
        self._in_stream   = self._p.open(
            format=pa.paInt16,
            channels=mic['maxInputChannels'],
            rate=self._sample_rate,
            input=True,
            input_device_index=mic['index'],
            frames_per_buffer=self._chunk_size,
            stream_callback=self.callback
        )

    def __del__(self):
        if not self._in_stream.is_stopped():
            self.stop_stream()
        
        self._in_stream.close()
        self._p.terminate()
    
    def __enter__(self):
        if self._in_stream.is_stopped():
            self.start_stream()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if not self._in_stream.is_stopped():
            self.stop_stream()

    @property
    def sample_rate(self):
        return self._sample_rate
    
    @property
    def chunk_size(self):
        return self._chunk_size

    def callback(self, data, frame_count, time_info, status):
        self._buffer.appendleft(np.frombuffer(data, dtype=np.int16))
        return data, pa.paContinue
    
    def start_stream(self):
        if self._in_stream.is_stopped():
            print("[INFO] Recording started")
            self._in_stream.start_stream()
        else:
            print("[INFO] Recording already in progress")

    def stop_stream(self):
        if not self._in_stream.is_stopped():
            print("[INFO] Recording stopped")
            self._in_stream.stop_stream()
        else:
            print("[INFO] Recording not in progress")

    def get_data(self):
        if len(self._buffer) > 0:
            return self._buffer.pop()
        else:
            return None


class AudioDataClient(object):
    def __init__(self):
        self._sample_rate      = config.getint('Audio', 'SampleRate')
        self._avg_buffer       = deque(maxlen=config.getint('Audio', 'FilterSize'))
        self._last_update_time = time.time()
        self._stream_fps       = config.getfloat('Audio', 'StreamFps')
        self._stream_period    = 1 / self._stream_fps
    
    def setup(self):
        server_url = f"http://{config['Audio']['ServerAddr']}:{config['Audio']['ServerPort']}"
        print(f"[INFO] Connecting to server {server_url}")
        sio.connect(
            server_url,
            transports=['websocket'],
            namespaces=[config['Namespaces']['Audio']]
        )

    def process_raw_audio(self, samples: np.ndarray):
        curr_time = time.time()
        if ((curr_time - self._last_update_time) > self._stream_period) and (samples is not None):
            self._last_update_time = curr_time

            win_size      = samples.shape[-1]
            real_win_size = int(win_size / 2)
            sp            = np.absolute(np.fft.fft(samples)[1:real_win_size])
            self._avg_buffer.appendleft(20 * np.log10(2 * np.abs(sp) / real_win_size))
            mags          = np.mean(self._avg_buffer, axis=0)
            freqs         = self._sample_rate * np.fft.fftfreq(win_size)[1:real_win_size]

            sio.emit(
                config['Channels']['Samples'],
                {
                    'freqs':   freqs.tolist(),
                    'mags':    mags.tolist(),
                    'samples': samples / 32768.0
                }
            )
            print(f"Max Freq: {freqs[mags.argmax()]} @ {mags.max()} dB")
    
    def close(self):
        sio.disconnect()


def main():
    try:
        audio_client = AudioDataClient()
        audio_client.setup()
        with MicrophoneReader() as ain:
            while True:
                audio_client.process_raw_audio(ain.get_data())

    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()

    # mic_reader = MicrophoneReader(chunk_size=args['chunk_size'])
    # mic_reader.start_stream()
    # fig, ax = plt.subplots()
    # ln, = plt.plot([], [])
    # avg_buffer = deque(maxlen=args['buffer_size'])
    # avg_buffer = np.zeros((args['filter_size'], args['chunk_size']//2 - 1), dtype=np.int16)

    # def init():
    #     ax.set_ylabel('Intensity (dB)')
    #     ax.set_xlabel('Frequency (Hz)')
    #     ax.set_ylim(-15, 100)
    #     ax.set_xlim(0, mic_reader.sample_rate_ / 2)
    #     plt.grid()
    #     return ln,

    # def update(frame):
    #     y = mic_reader.get_data()
    #     if y is not None:
    #         win_size      = y.shape[-1]
    #         real_win_size = int(win_size / 2)
    #         sp            = np.absolute(np.fft.fft(y)[1:real_win_size])
    #         avg_buffer[buffer_position, :] = 20 * np.log10(2 * np.abs(sp) / real_win_size)
    #         mags          = avg_buffer.mean(axis=0)
    #         freqs         = 48e3 * np.fft.fftfreq(win_size)[1:real_win_size]
    #         ln.set_data(freqs, mags)
    #         #print(f"Max Freq: {freqs[mags.argmax()]} @ {mags.max()} dB")

    #     return ln,

    # ani = FuncAnimation(fig, update, blit=True, interval=30, init_func=init)
    # try:
    #     plt.show()

    # except KeyboardInterrupt:
    #     print("Caught Ctrl-C")
    # finally:
    #     mic_reader.stop_stream()

