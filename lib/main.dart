import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final firstCamera = cameras.first;

  await dotenv.load(fileName: ".env");

  runApp(
    MaterialApp(
      theme: ThemeData.dark(),
      home: TakePictureScreen(
        camera: firstCamera,
      ),
    ),
  );
}

class TakePictureScreen extends StatefulWidget {
  const TakePictureScreen({
    super.key,
    required this.camera,
  });

  final CameraDescription camera;

  @override
  TakePictureScreenState createState() => TakePictureScreenState();
}

class TakePictureScreenState extends State<TakePictureScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;

  FlutterTts flutterTts = FlutterTts();
  String display = '';

  SpeechToText speechToText = SpeechToText();
  bool speechEnabled = false;
  String transcript = '';

  bool isBusy = false;

  void _initSpeech() async {
    speechEnabled = await speechToText.initialize();
    setState(() {});
  }

  void _startListening() async {
    transcript = "";
    flutterTts.stop();
    await speechToText.listen(onResult: _onSpeechResult);
    setState(() {});
  }

  void _stopListening() async {
    await speechToText.stop();
    await Future.delayed(const Duration(seconds: 1));
    setState(() {
      display = transcript;
    });

    if (transcript != "") {
      isBusy = true;
      final imageBytes = await takePicture();
      final response = await analyzeImage(imageBytes);
      isBusy = false;
      speak(response);
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      transcript = result.recognizedWords;
    });
  }

  @override
  void initState() {
    super.initState();
    _initSpeech();

    _controller = CameraController(
      widget.camera,
      ResolutionPreset.high,
    );

    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> speak(text) async {
    setState(() {
      display = text;
    });
    await flutterTts.speak(text);
  }

  Future<String> takePicture() async {
    final image = await _controller.takePicture();
    final imageFile = File(image.path);
    final imageBytes = await imageFile.readAsBytes();
    String base64Img = base64Encode(imageBytes);
    return base64Img;
  }

  Future<String?> analyzeImage(base64Img) async {
    final apiKey = dotenv.env['GOOGLE_API_KEY'];
    final headers = {'Content-Type': 'application/json'};
    final request = http.Request(
        'POST',
        Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/gemini-pro-vision:generateContent?key=$apiKey'));
    request.body = json.encode({
      "contents": [
        {
          "parts": [
            {
              "text":
                  '''Analyze the image and answer the question below. If the image is unrelated, 
            ignore it and answer based on textual knowledge. Keep your response as concise as possible.
            Question: $transcript '''
            },
            {
              "inline_data": {"mime_type": "image/jpeg", "data": base64Img}
            }
          ]
        }
      ]
    });
    request.headers.addAll(headers);

    http.StreamedResponse response = await request.send();

    if (response.statusCode == 200) {
      final jsonString = await response.stream.bytesToString();
      final jsonResponse = jsonDecode(jsonString);
      return jsonResponse['candidates'][0]['content']['parts'][0]['text'];
    } else {
      return response.reasonPhrase;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gemini Lens 👀')),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<void>(
              future: _initializeControllerFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  return Center(child: CameraPreview(_controller));
                } else {
                  return const Center(child: CircularProgressIndicator());
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              display,
              style: const TextStyle(fontSize: 20),
            ),
          ),
        ],
      ),
      floatingActionButton: speechEnabled
          ? SizedBox(
              width: 80.0, // Increased width
              height: 80.0, // Increased height
              child: FloatingActionButton(
                onPressed: () {
                  if (isBusy == false) {
                    if (speechToText.isNotListening) {
                      _startListening();
                    } else {
                      _stopListening();
                    }
                  }
                },
                backgroundColor: Colors.blueAccent,
                child: Icon(
                  isBusy
                      ? Icons.do_not_disturb
                      : speechToText.isNotListening
                          ? Icons.mic_off
                          : Icons.mic,
                  size: 50,
                ),
              ),
            )
          : const Text('Speech Recognition Failed'),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
