#!/usr/bin/env python

import time
import numpy as np
import pyaudio as pa
import matplotlib.pyplot as plt
from matplotlib.animation import FuncAnimation
from collections import deque


class MicrophoneReader(object):
    def __init__(self, chunk_size: int = 1024, buffer_size: int = 1024):
        self.buffer_size_ = buffer_size
        self._buffer      = deque(maxlen=buffer_size)
        self._p           = pa.PyAudio()
        mic               = self._p.get_default_input_device_info()
        self.sample_rate_ = int(mic['defaultSampleRate'])
        self._in_stream   = self._p.open(
            format=pa.paInt16,
            channels=mic['maxInputChannels'],
            rate=self.sample_rate_,
            input=True,
            frames_per_buffer=chunk_size,
            stream_callback=self.callback
        )

    def __del__(self):
        self._in_stream.close()
        self._p.terminate()

    def callback(self, data, frame_count, time_info, status):
        self._buffer.appendleft(np.frombuffer(data, dtype=np.int16))
        return data, pa.paContinue
    
    def start_stream(self):
        print("***** Recording *****")
        self._in_stream.start_stream()

    def stop_stream(self):
        print("***** Recording Stopped *****")
        self._in_stream.stop_stream()

    def get_data(self):
        if len(self._buffer) > 0:
            return self._buffer.pop()
        else:
            return None


if __name__ == "__main__":
    chunk = 2048
    mic_reader = MicrophoneReader(chunk_size=chunk)
    mic_reader.start_stream()
    fig, ax = plt.subplots()
    ln, = plt.plot([], [])
    buffer_position = 0
    avg_buffer = np.zeros((10, chunk//2 - 1), dtype=np.int16)

    def init():
        ax.set_ylabel('Intensity (dB)')
        ax.set_xlabel('Frequency (Hz)')
        ax.set_ylim(-15, 100)
        ax.set_xlim(0, mic_reader.sample_rate_ / 2)
        plt.grid()
        return ln,

    def update(frame):
        y = mic_reader.get_data()
        if y is not None:
            win_size      = y.shape[-1]
            real_win_size = int(win_size / 2)
            sp            = np.absolute(np.fft.fft(y)[1:real_win_size])
            avg_buffer[buffer_position, :] = 20 * np.log10(2 * np.abs(sp) / real_win_size)
            mags          = avg_buffer.mean(axis=0)
            freqs         = 48e3 * np.fft.fftfreq(win_size)[1:real_win_size]
            ln.set_data(freqs, mags)
            #print(f"Max Freq: {freqs[mags.argmax()]} @ {mags.max()} dB")

        return ln,

    ani = FuncAnimation(fig, update, blit=True, interval=30, init_func=init)
    try:
        plt.show()

    except KeyboardInterrupt:
        print("Caught Ctrl-C")
    finally:
        mic_reader.stop_stream()

