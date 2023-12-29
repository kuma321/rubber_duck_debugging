import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:convert';
import 'env/env.dart';
import 'package:audioplayers/audioplayers.dart';

Future main() async {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'ChatGPT Demo',
      home: ChatScreen(),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUserMessage;

  ChatMessage({required this.text, required this.isUserMessage});
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  ChatScreenState createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();

  FlutterTts flutterTts = FlutterTts();

  List<ChatMessage> messages = [];

  late stt.SpeechToText _speech;

  bool _isListening = false;

  String _text = '';

  // チャットGPTのAPIからの返答を保持する
  String aiResponse = '';

  bool _isLoading = false;

  String micText = "";

  final FocusNode _focusNode = FocusNode();

  //音声再生
  final audioPlayer = AudioPlayer();

  //連続タップ抑制
  bool _waiting = false;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
  }

  Future<String> sendMessage(String messageText) async {
    final String apikey = Env.key;
    setState(() {
      _isLoading = true;
    });

    showDialog(
      context: context,
      barrierDismissible: false, // ユーザーがダイアログ外をタップして閉じないようにする
      builder: (BuildContext context) {
        return const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text("データを取得しています..."),
            ],
          ),
        );
      },
    );
    var response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json ',
        'Authorization': 'Bearer $apikey',
      },
      body: jsonEncode({
        'model': 'gpt-3.5-turbo',
        'messages': [
          {
            'role': 'system',
            'content': 'ラバーダック・デバッグのための聞き手として話を聞いてください。',
          },
          {
            'role': 'user',
            'content': messageText,
          },
        ]
      }),
    );

    if (response.statusCode == 200) {
      var data = jsonDecode(utf8.decode(response.bodyBytes));
      var decodedText = data['choices'][0]['message']['content'].toString();
      _speak(decodedText);
      return decodedText;
    } else {
      return 'Failed to fetch response';
    }
  }

  Future _speak(String text) async {
    await flutterTts.setLanguage('ja-JP'); // 読み上げる言語を設定
    await flutterTts.setSpeechRate(0.55); // 読み上げ速度を設定
    await flutterTts.setVolume(5.0); // 音量を設定

    debugPrint("====  API response text $text");
    await flutterTts.speak(text); // テキストを読み上げ
  }

  void addMessageToList(String text, bool isUserMessage) {
    if (_isLoading) Navigator.pop(context); // APIからのメッセージを受信した場合はダイアログを閉じるため
    setState(() {
      messages.add(ChatMessage(text: text, isUserMessage: isUserMessage));
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // GestureDetectorで画面全体をラップ
      onTap: () {
        // タップ時にフォーカスを外す（キーボードを非表示にする）
        _focusNode.unfocus();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(' Rubber duck debugging '),
          backgroundColor: Colors.orange,
        ),
        body: Column(
          children: <Widget>[
            Expanded(
              child: ListView.builder(
                itemCount: messages.length,
                itemBuilder: (BuildContext context, int index) {
                  var message = messages[index];
                  return ListTile(
                    title: Container(
                      alignment: message.isUserMessage
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      margin: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 8),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: message.isUserMessage
                              ? Colors.blue
                              : Colors.green[400], // 自分のメッセージと相手のメッセージで色を変える
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          message.text,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              color: Colors.brown[50],
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        decoration: const InputDecoration(
                          hintText: 'メッセージを入力してください',
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: _waiting
                          ? null
                          : () async {
                              setState(() => _waiting = true); //ボタンを無効
                              _text = _controller.text;
                              if (_text.isNotEmpty) {
                                audioPlayer.play(
                                    AssetSource("SendingTextSoundEffect.mp3"));
                                addMessageToList(_text, true);
                                aiResponse = await sendMessage(_text);
                                addMessageToList(aiResponse, false);
                                _controller.clear();
                                _text = "";
                              }
                              setState(() => _waiting = false); //ボタンを有効
                            },
                    ),
                    IconButton(
                      icon: const Icon(Icons.mic),
                      onPressed: _waiting
                          ? null
                          : () async {
                              setState(() => _waiting = true); //ボタンを無効
                              showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    content: GestureDetector(
                                      behavior: HitTestBehavior.translucent,
                                      onTap: () {
                                        stop();
                                      },
                                      child: const Row(
                                        children: [
                                          CircularProgressIndicator(),
                                          SizedBox(width: 40),
                                          Text(
                                              "音声入力中です... \n中止するには\nタップしてください"),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                              _listen();
                              setState(() => _waiting = false); //ボタンを有効
                            },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

// 音声入力を行う
  Future<void> _listen() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (status) {
          debugPrint('====  onStatus: $status');
        },
        onError: (error) {
          debugPrint('==== onError: $error ');
        },
      );

      if (available) {
        setState(() {
          _isListening = true;
        });

        _speech.listen(
          onResult: (result) {
            setState(() {
              audioPlayer.play(AssetSource("CompletionSoundEffect.mp3"));
              micText = result.recognizedWords;
            });
            // 音声入力が終了したら、ここで停止する
            _speech.stop();
            send();
            setState(() {
              _isListening = false;
            });
          },
          localeId: 'ja_JP', //音声入力を日本語に指定する
        );
      }
    }
  }

  // 音声入力を中断する処理
  void stop() {
    debugPrint("音声入力を中断しました。");
    _speech.stop();
    Navigator.pop(context);
  }

  void send() async {
    addMessageToList(micText, true);
    aiResponse = await sendMessage(micText);
    addMessageToList(aiResponse, false);
    micText = "";
  }
}
