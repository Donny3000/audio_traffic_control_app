import 'dart:async';
import 'dart:math';
import 'dart:io' as dio;
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:sound_meter/src/resources/resources.dart';
//import 'dart:io' as io; // To detect platform
import 'package:flutter/foundation.dart' show kIsWeb; // To detect web platform
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

import 'package:socket_io_client/socket_io_client.dart' as io;

class AudioSpectrum extends StatefulWidget {
  const AudioSpectrum({super.key});

  final Color sinColor = SMColors.contentColorBlue;
  final Color cosColor = SMColors.contentColorPink;

  @override
  State<AudioSpectrum> createState() => _AudioSpectrumState();
}

class _AudioSpectrumState extends State<AudioSpectrum> {
  final limitCount            = 100;
  final sinPoints             = <FlSpot>[];
  final cosPoints             = <FlSpot>[];
  final amplitudes            = <FlSpot>[];
  final int maxAmplitudes     = 100;
  final List<int> sampleRates = [8000, 16000, 32000, 44100, 48000];
  final logger                = Logger(
    printer: PrettyPrinter(methodCount: 0),
  );

  // Configurable parameters
  int sampleRate = 44100; // Default sample rate
  int bufferSize = 1024; // Default buffer size

  double xValue = 0;
  double step = 0.05;

  late io.Socket socket;
  //late Timer timer;

  @override
  void initState() {
    super.initState();
    _connectToSocket();
    // timer = Timer.periodic(const Duration(milliseconds: 40), (timer) {
    //   while (sinPoints.length > limitCount) {
    //     sinPoints.removeAt(0);
    //     cosPoints.removeAt(0);
    //   }
    //   setState(() {
    //     amplitudes.add(FlSpot(xValue, sin(xValue)));
    //     //sinPoints.add(FlSpot(xValue, cos(xValue)));
    //     //cosPoints.add(FlSpot(xValue, cos(xValue)));
    //   });
    //   xValue += step;
    // });
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

    socket.on('audio_stream', (data) {
      // Handle incoming audio data
      _updateWaveform(Int16List.fromList(List<int>.from(data['samples'])));
    });

    socket.on('audio_error', (data) {
      logger.e('Audio error: $data');
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
  void _updateWaveform(Int16List data) {
    // Extract amplitude from raw audio data for waveform visualization
    final int16List = Int16List.view(data.buffer); // Assuming 16-bit PCM format
    // final double maxAmplitude =
    //     int16List.map((v) => v.abs()).reduce(max).toDouble();
    
    setState(() {
      xValue = 0;
      for (var sample in int16List) {
        amplitudes.add(FlSpot(xValue, sample.toDouble()));
      }
    });

    // setState(() {
    //   amplitudes.add(maxAmplitude);
    //   if (amplitudes.length > maxAmplitudes) {
    //     amplitudes.removeAt(0); // Keep the amplitude list size manageable
    //   }
    // });
  }

  void _startAudioStream() {
    // Send user-selected parameters to the server
    socket.emit(
        'start_audio', {'sample_rate': sampleRate, 'buffer_size': bufferSize});
  }

  void _stopAudioStream() {
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
        /////////////////////////////
        // Setup the Flutter graph //
        /////////////////////////////
        amplitudes.isNotEmpty ? AspectRatio(
          aspectRatio: 1.5,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24.0),
            child: LineChart(
              LineChartData(
                minY: -1,
                maxY: 1,
                minX: amplitudes.first.x,
                maxX: amplitudes.last.x,
                lineTouchData: const LineTouchData(enabled: false),
                clipData: const FlClipData.all(),
                gridData: const FlGridData(
                  show: true,
                  drawVerticalLine: false,
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  ampLine(amplitudes)
                  // sinLine(sinPoints),
                  // cosLine(cosPoints),
                ],
                titlesData: const FlTitlesData(
                  show: false,
                ),
              ),
            ),
          ),
        ) : Container(),
      ],
    );
  }

  LineChartBarData ampLine(List<FlSpot> points) {
    return LineChartBarData(
      spots: points,
      dotData: const FlDotData(
        show: false,
      ),
      gradient: LinearGradient(
        colors: [widget.cosColor.withValues(alpha: 0), widget.cosColor],
        stops: const [0.1, 1.0],
      ),
      barWidth: 4,
      isCurved: false,
    );
  }

  // LineChartBarData sinLine(List<FlSpot> points) {
  //   return LineChartBarData(
  //     spots: points,
  //     dotData: const FlDotData(
  //       show: false,
  //     ),
  //     gradient: LinearGradient(
  //       colors: [widget.sinColor.withValues(alpha: 0), widget.sinColor],
  //       stops: const [0.1, 1.0],
  //     ),
  //     barWidth: 4,
  //     isCurved: false,
  //   );
  // }

  // LineChartBarData cosLine(List<FlSpot> points) {
  //   return LineChartBarData(
  //     spots: points,
  //     dotData: const FlDotData(
  //       show: false,
  //     ),
  //     gradient: LinearGradient(
  //       colors: [widget.cosColor.withValues(alpha: 0), widget.cosColor],
  //       stops: const [0.1, 1.0],
  //     ),
  //     barWidth: 4,
  //     isCurved: false,
  //   );
  // }

  @override
  void dispose() {
    socket.dispose();
    super.dispose();
  }
}
