import 'dart:async';
//import 'dart:collection';
//import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' as io;                               // To detect platform
import 'package:flutter/foundation.dart' show kIsWeb; // To detect web platform
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:socket_io_client/socket_io_client.dart' as io;
//import 'package:audioplayers/audioplayers.dart';
//import 'package:audioplayers/audio_cache.dart';

//import 'sample_feature/sample_item_details_view.dart';
//import 'sample_feature/sample_item_list_view.dart';
import 'settings/settings_controller.dart';
import 'resources/texts.dart';
//import 'settings/settings_view.dart';
import 'package:logger/logger.dart';

/// The Widget that configures your application.
class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.settingsController,
  });

  final SettingsController settingsController;

  @override
  Widget build(BuildContext context) {
    // Glue the SettingsController to the MaterialApp.
    //
    // The ListenableBuilder Widget listens to the SettingsController for changes.
    // Whenever the user updates their settings, the MaterialApp is rebuilt.
    return ListenableBuilder(
      listenable: settingsController,
      builder: (BuildContext context, Widget? child) {
        return MaterialApp(
          // Providing a restorationScopeId allows the Navigator built by the
          // MaterialApp to restore the navigation stack when a user leaves and
          // returns to the app after it has been killed while running in the
          // background.
          restorationScopeId: 'app',

          // Provide the generated AppLocalizations to the MaterialApp. This
          // allows descendant Widgets to display the correct translations
          // depending on the user's locale.
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en', ''), // English, no country code
          ],

          // Use AppLocalizations to configure the correct application title
          // depending on the user's locale.
          //
          // The appTitle is defined in .arb files found in the localization
          // directory.
          onGenerateTitle: (BuildContext context) =>
              AppLocalizations.of(context)!.appTitle,

          // Define a light and dark color theme. Then, read the user's
          // preferred ThemeMode (light, dark, or system default) from the
          // SettingsController to display the correct theme.
          theme: ThemeData(),
          darkTheme: ThemeData.dark(),
          themeMode: settingsController.themeMode,

          home: const AudioStreamPage(),
        );
      },
    );
  }
}

class AudioStreamPage extends StatefulWidget {
  const AudioStreamPage({super.key});

  @override
  _AudioStreamPageState createState() => _AudioStreamPageState();
}

class _AudioStreamPageState extends State<AudioStreamPage> {
  late io.Socket socket;
  //late AudioPlayer audioPlayer;
  //late Queue<Uint16List> audioBuffer;
  Timer? playbackTimer;
  List<double> amplitudes = [];
  final int maxAmplitudes = 100;
  final Logger logger     = Logger(
    printer: PrettyPrinter(methodCount: 0),
  );

  // Configurable parameters
  int sampleRate = 44100; // Default sample rate
  int bufferSize = 1024; // Default buffer size
  final List<int> sampleRates = [8000, 16000, 32000, 44100, 48000];

  @override
  void initState() {
    super.initState();
    //audioPlayer = AudioPlayer();
    //audioBuffer = Queue<Uint16List>();
    _connectToSocket();
  }

  @override
  void dispose() {
    socket.dispose();
    playbackTimer?.cancel();
    //audioPlayer.dispose();
    super.dispose();
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
      _updateWaveform(
        Int16List.fromList(
          List<int>.from(data['samples'])
        )
      );
      // if (data is Uint16List) {
      //   _addToBuffer(data);
      //   _updateWaveform(data);
      // }
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
    } else if (io.Platform.isAndroid || io.Platform.isIOS) {
      // Mobile platforms: Ensure the IP address is reachable from the device
      return baseUrl;
    } else if (io.Platform.isWindows ||
        io.Platform.isLinux ||
        io.Platform.isMacOS) {
      // Desktop platforms: Adjust settings if needed
      return baseUrl;
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  // void _addToBuffer(Uint16List data) {
  //   // Add audio chunk to the buffer
  //   audioBuffer.add(data);
  //   // Start playback if not already running
  //   if (playbackTimer == null || !playbackTimer!.isActive) {
  //     _startBufferedPlayback();
  //   }
  // }

  // void _startBufferedPlayback() {
  //   playbackTimer = Timer.periodic(const Duration(milliseconds: 50), (_) async {
  //     if (audioBuffer.isNotEmpty) {
  //       final chunk = audioBuffer.removeFirst();
  //       await audioPlayer.playBytes(chunk);
  //     } else {
  //       playbackTimer?.cancel();
  //     }
  //   });
  // }

  void _updateWaveform(Int16List data) {
    // Extract amplitude from raw audio data for waveform visualization
    final int16List = Int16List.view(data.buffer); // Assuming 16-bit PCM format
    final double maxAmplitude =
        int16List.map((v) => v.abs()).reduce(max).toDouble();

    setState(() {
      amplitudes.add(maxAmplitude);
      if (amplitudes.length > maxAmplitudes) {
        amplitudes.removeAt(0); // Keep the amplitude list size manageable
      }
    });
  }

  void _startAudioStream() {
    // Send user-selected parameters to the server
    socket.emit('start_audio', {
      'sample_rate': sampleRate,
      'buffer_size': bufferSize
    });
  }

  void _stopAudioStream() {
    socket.emit('stop_audio');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(SMTexts.appName),
      ),
      body: Column(
        children: [
          // Waveform visualization
          Expanded(
            child: Center(
              child: CustomPaint(
                size: const Size(double.infinity, 200),
                painter: WaveformPainter(amplitudes),
              ),
            ),
          ),
          // Configurable parameters UI
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
          // Start/Stop buttons
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
        ],
      ),
    );
  }
}

class WaveformPainter extends CustomPainter {
  final List<double> amplitudes;

  WaveformPainter(this.amplitudes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    if (amplitudes.isNotEmpty) {
      final double step = size.width / amplitudes.length;

      for (int i = 0; i < amplitudes.length; i++) {
        final x = i * step;
        final y = size.height / 2 - amplitudes[i] / 32768 * (size.height / 2);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
