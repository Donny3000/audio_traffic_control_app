import 'dart:io' as dio; // To detect platform
import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // To detect web platform
import 'package:logger/logger.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'package:sound_meter/src/resources/resources.dart';

class AudioSpectrum extends StatefulWidget {
  const AudioSpectrum({super.key});

  final Color amplitudeColor = SMColors.contentColorWhite;

  @override
  State<AudioSpectrum> createState() => _AudioSpectrumState();
}

class _AudioSpectrumState extends State<AudioSpectrum> {
  final samples               = <FlSpot>[];
  //final int maxAmplitudes     = 100;
  final List<int> sampleRates = [8000, 16000, 32000, 44100, 48000];
  final logger                = Logger(
    printer: PrettyPrinter(methodCount: 0),
  );

  // Configurable parameters
  int sampleRate = 44100; // Default sample rate
  int bufferSize = 1024; // Default buffer size

  // Create the websocket to communicate with the server
  late io.Socket socket;

  // Widget for the left-side axis labels
  Widget leftTitleWidgets(double value, TitleMeta meta, double chartWidth) {
    final style = TextStyle(
      color: SMColors.contentColorYellow,
      fontWeight: FontWeight.bold,
      fontSize: min(18, 18 * chartWidth / 300),
    );
    return SideTitleWidget(
      axisSide: meta.axisSide,
      space: 16,
      child: Text(meta.formattedValue, style: style),
    );
  }


  // Widget for the bottom axis label
  Widget bottomTitleWidgets(double value, TitleMeta meta, double chartWidth) {
    if (value % 5000 != 0) {
      return Container();
    }
    final style = TextStyle(
      color: SMColors.contentColorBlue,
      fontWeight: FontWeight.bold,
      fontSize: min(18, 18 * chartWidth / 300),
    );
    return SideTitleWidget(
      axisSide: meta.axisSide,
      space: 16,
      child: Text(meta.formattedValue, style: style),
    );
  }

  @override
  void initState() {
    super.initState();
    _connectToSocket();
  }

  void _connectToSocket() {
    // Determine WebSocket URL based on platform
    final String serverUrl = _getServerUrl();

    // Connect to the Flask-SocketIO server
    socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket']) // Use WebSocket transport
          .disableAutoConnect() // Prevent auto-connection
          .build(),
    );

    // Set up socket listeners
    socket.onConnect((_) {
      logger.i('Connected to server');
    });

    socket.onError(       (err) => logger.e(err));
    socket.onConnectError((err) => logger.e(err));

    socket.on('audio_stream', (data) {
      // Handle incoming audio data
      _updateWaveform(
        Float64List.fromList(List<double>.from(data['freqs'])),
        Float64List.fromList(List<double>.from(data['mags']))
      );
    });

    socket.on('audio_error', (err) {
      logger.e('Audio error: $err');
    });

    socket.onDisconnect((_) {
      logger.i('Disconnected from server');
    });

    socket.connect();
  }

  String _getServerUrl() {
    const String baseUrl = 'ws://black-mamba.lan:5001';

    if (kIsWeb) {
      // Web-specific URL (no change needed)
      return baseUrl;
    } else if (dio.Platform.isAndroid || dio.Platform.isIOS) {
      // Mobile platforms: Ensure the IP address is reachable from the device
      return baseUrl;
    } else if (dio.Platform.isWindows ||
        dio.Platform.isLinux ||
        dio.Platform.isMacOS) {
      // Desktop platforms: Adjust settings if needed
      return baseUrl;
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }
  void _updateWaveform(Float64List frequencyData, Float64List sampleData) {
    // Extract amplitude from raw audio data for waveform visualization
    final frequencyView  = Float64List.view(frequencyData.buffer);
    final sampleView     = Float64List.view(sampleData.buffer); // Assuming 16-bit PCM format

    // Clear the current amplitude data to make way for the new amplitudes
    samples.clear();
    
    setState(() {
      for (var i = 0; i < sampleView.length; i++) {
        samples.add(FlSpot(frequencyView[i], sampleView[i]));//.toDouble() / 32768.0));
      }
    });
  }

  void _startAudioStream() {
    // Send user-selected parameters to the server
    if (!socket.connected) {
      logger.w("Not connected to server. May fail to start audio.");
    }

    socket.emit(
      'start_audio', {'sample_rate': sampleRate, 'buffer_size': bufferSize}
    );
  }

  void _stopAudioStream() {
    if (!socket.connected) {
      logger.w("Not connected to server. May fail to stop audio.");
    }

    socket.emit('stop_audio');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 12),
          ////////////////////////////////
          // Configurable parameters UI //
          ////////////////////////////////
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Sample Rate:'),
                    DropdownButton<int>(
                      value: sampleRate,
                      items: sampleRates
                          .map((rate) => DropdownMenuItem(
                                value: rate,
                                child: Text('$rate Hz'),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            sampleRate = value;
                          });
                        }
                      },
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Buffer Size:'),
                    Slider(
                      value: bufferSize.toDouble(),
                      min: 256,
                      max: 2048,
                      divisions: 7,
                      label: '$bufferSize',
                      onChanged: (value) {
                        setState(() {
                          bufferSize = value.toInt();
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          ////////////////////////
          // Start/Stop buttons //
          ////////////////////////
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: _startAudioStream,
                child: const Text('Start Audio Stream'),
              ),
              ElevatedButton(
                onPressed: _stopAudioStream,
                child: const Text('Stop Audio Stream'),
              ),
            ],
          ),
          ////////////////////////////////////////
          // Padding between controls and graph //
          ////////////////////////////////////////
          const SizedBox(height: 12),
          /////////////////////////////
          // Setup the Flutter graph //
          /////////////////////////////
          samples.isNotEmpty ? Expanded(
            child: AspectRatio(
              aspectRatio: 1.5,
              child: LayoutBuilder(
                //padding: const EdgeInsets.only(bottom: 24.0),
                //child: LineChart(
                builder: (context, constraints) {
                  return LineChart(
                    LineChartData(
                    minY: -40,
                    maxY: 50,
                    minX: 0,
                    maxX: samples.last.x,
                    lineTouchData: const LineTouchData(enabled: false),
                    clipData: const FlClipData.all(),
                    gridData: const FlGridData(
                      show: true,
                      drawVerticalLine: false,
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      ampLine(samples)
                    ],
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) =>
                            leftTitleWidgets(value, meta, constraints.maxWidth),
                          reservedSize: 56,
                        ),
                        drawBelowEverything: true,
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) =>
                            bottomTitleWidgets(value, meta, constraints.maxWidth),
                          reservedSize: 36,
                          interval: 1,
                        ),
                        drawBelowEverything: true,
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                  ),
                );
              }
              ),
            )
          ) : Container()
        ],
      );
  }

  LineChartBarData ampLine(List<FlSpot> points) {
    return LineChartBarData(
      spots: points,
      dotData: const FlDotData(
        show: false,
      ),
      color: widget.amplitudeColor,
      barWidth: 4,
      isCurved: false,
      belowBarData: BarAreaData(
        show: true,
        color: widget.amplitudeColor.withValues(alpha: 0.3)
      )
    );
  }

  @override
  void dispose() {
    socket.dispose();
    super.dispose();
  }
}
