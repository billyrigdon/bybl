import 'dart:async';
import 'dart:convert';
import 'package:TheWord/screens/main_app.dart';
import 'package:TheWord/screens/saved_verses.dart';
import 'package:TheWord/shared/widgets/highlight_text.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/settings_provider.dart';
import '../services/chat_service.dart';

class ReaderScreen extends StatefulWidget {
  String chapterId;
  final String chapterName;
  final List<dynamic> chapterIds;
  final List<String> chapterNames;
  final String bookName;

  ReaderScreen({
    required this.chapterId,
    required this.chapterName,
    required this.chapterIds,
    required this.chapterNames,
    required this.bookName,
  });

  @override
  ReaderScreenState createState() => ReaderScreenState();
}

class ReaderScreenState extends State<ReaderScreen> {
  // final String scriptureApiKey = dotenv.env['BIBLE_KEY'] ?? '';
  // final String esvApiKey = dotenv.env['ESV_KEY'] ?? '';

  late PageController _pageController;

  Map<String, List<Map<String, dynamic>>> _chapterContents = {};

  bool isLoading = true;
  bool isSummaryLoading = false;

  bool isReading = false;
  bool isPaused = false;
  bool isSkipping = false;
  int? currentVerseIndex;

  int currentPageIndex = 0;
  String chapterName = '';
  bool pageChanging = false;

  FlutterTts flutterTts = FlutterTts();

  ChatService chatService = ChatService();

  bool savedVersesActive = false;

  final GlobalKey<SelectableTextHighlightState> highlightKey =
      GlobalKey<SelectableTextHighlightState>();

  final Map<String, ScrollController> _scrollControllers = {};

  @override
  void initState() {
    super.initState();

    chapterName = widget.chapterName;

    _pageController = PageController(
      initialPage: widget.chapterIds.indexOf(widget.chapterId),
    );

    _fetchChapterContent(widget.chapterId);
    _preloadAdjacentChapters(widget.chapterId);

    flutterTts.setCompletionHandler(() {
      if (!isSkipping) {
        _readNextVerse();
      }
      isSkipping = false;
    });

    flutterTts.setSpeechRate(0.5);
    flutterTts.setPitch(1.0);
    flutterTts.setLanguage('en-US');
    flutterTts.awaitSpeakCompletion(true);
  }

  @override
  void dispose() {
    flutterTts.stop();
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  ScrollController _getScrollController(String chapterId) {
    return _scrollControllers.putIfAbsent(chapterId, () => ScrollController());
  }

  String? _lastPreloadedChapterId;

  Future<void> _fetchChapterContent(String chapterId,
      {bool showLoading = true}) async {
    print(chapterId);
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    final translationId = settingsProvider.currentTranslationId ?? '';

    if (_chapterContents.containsKey(chapterId)) {
      if (chapterId == widget.chapterId) {
        setState(() => isLoading = false);
      }
      return;
    }

    if (showLoading) {
      setState(() => isLoading = true);
    }

    try {
      final response = await http.get(Uri.parse(
        'https://api.bybl.dev/api/passage/$translationId?q=$chapterId',
      ));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final rawContent = data['data']['content'];

        if (rawContent is! List) {
          _chapterContents[chapterId] = [];
        } else {
          final verses = _extractScriptureApiVerses(rawContent);

          if (translationId.toUpperCase() == 'ESV') {
            for (final v in verses) {
              final parts = (v['id'] as String).split('.');
              v['id'] = parts.isNotEmpty ? parts.last : v['id'];
            }
          }

          _chapterContents[chapterId] = verses;
        }
      } else {
        _chapterContents[chapterId] = [];
      }
    } catch (e, stack) {
      _chapterContents[chapterId] = [];
    } finally {
      if (showLoading && chapterId == widget.chapterId) {
        setState(() => isLoading = false);
      }
    }
  }

  _fetchChapterVersesFromBackend(String chapterId, String translationId) async {
    final reference = chapterId.replaceAll('.', ' ');
    final isEsv = translationId.toUpperCase() == 'ESV';
    final uri = Uri.parse(
      isEsv
          ? 'https://api.bybl.dev/api/passage/$translationId?q=$reference'
          : 'https://api.bybl.dev/api/bible/$translationId/chapters/$chapterId?content-type=json',
    );

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch chapter content');
    }

    final data = json.decode(response.body);

    if (isEsv) {
      final passages = (data['data'] as List)
          .map((item) => item['content'] as String)
          .join('\n')
          .trim();
      return _parseEsvVerses(passages);
    } else {
      final rawContent = data['data']['content'];
      return _extractScriptureApiVerses(rawContent);
    }
  }

  List<Map<String, dynamic>> _extractScriptureApiVerses(dynamic raw) {
    final verses = <Map<String, dynamic>>[];
    String? activeId; // track current verse-id

    for (final para in (raw as List)) {
      if (para is! Map || para['name'] != 'para') continue;

      for (final item in (para['items'] as List)) {
        // ── ① a normal “verse” wrapper ─────────────────────────────
        if (item['name'] == 'verse' && item['attrs'] is Map) {
          activeId = item['attrs']['sid'] ?? item['attrs']['verseId'];
          final buf = StringBuffer();
          for (final t in (item['items'] as List? ?? const [])) {
            if (t['type'] == 'text') buf.write(t['text'] ?? '');
          }
          final txt = buf
              .toString()
              .trim()
              .replaceFirst(RegExp(r'^\s*\[?\d+\]?'), ''); // drop [7]

          if (activeId != null && txt.isNotEmpty) {
            _appendOrMergeVerse(verses, activeId!, txt);
          }
          continue;
        }

        // ── ② a stand-alone text node (often Scripture-API “partial”) ──
        if (item['type'] == 'text') {
          final txt = (item['text'] ?? '').trim();
          if (txt.isEmpty) continue;

          // explicit verseId wins, otherwise fall back to current
          final vId = (item['attrs']?['verseId'] ?? activeId) as String?;
          if (vId != null && vId.isNotEmpty) {
            _appendOrMergeVerse(verses, vId, txt);
            activeId = vId; // keep tracking
          }
        }
      }
    }
    return verses;
  }

  List<Map<String, dynamic>> _parseEsvVerses(String esvText) {
    final List<Map<String, dynamic>> verses = [];

    // Replace new-lines with spaces so we can split cleanly
    final cleaned = esvText.replaceAll('\n', ' ').trim();

    // Match any sequence like 1 … 2 … 3 …
    final regex = RegExp(r'\s*(\d+)\s+');
    final matches = regex.allMatches(cleaned);

    for (int i = 0; i < matches.length; i++) {
      final start = matches.elementAt(i).end;
      final end = (i + 1 < matches.length)
          ? matches.elementAt(i + 1).start
          : cleaned.length;

      final verseNum = matches.elementAt(i).group(1)!; // "3"
      final verseText = cleaned.substring(start, end).trim(); // text of verse

      if (verseText.isNotEmpty) {
        verses.add({'id': verseNum, 'text': verseText});
      }
    }

    // Fallback (entire chapter as one verse) – rarely needed
    if (verses.isEmpty && cleaned.isNotEmpty) {
      verses.add({'id': '1', 'text': cleaned});
    }

    return verses;
  }

// ──────────────────────────────────────────────────────────────────────────────
// 2.  Helper used by _extractScriptureApiVerses
//     Converts IDs like "NUM 2:3"  →  "NUM.2.3"
//     so SelectableTextHighlight works the same way it always has.
// ──────────────────────────────────────────────────────────────────────────────
  void _appendOrMergeVerse(
      List<Map<String, dynamic>> verses, String rawId, String verseText) {
    // normalise: spaces & colons → dots
    final normId = rawId.replaceAll(RegExp(r'[: ]'), '.');

    final existingIdx = verses.indexWhere((v) => v['id'] == normId);
    if (existingIdx != -1) {
      verses[existingIdx]['text'] =
          '${verses[existingIdx]['text']} $verseText'.trim();
    } else {
      verses.add({'id': normId, 'text': verseText});
    }
  }

  void _startReading() {
    final content = _chapterContents[widget.chapterId];
    if (content == null || content.isEmpty) return;

    setState(() {
      isReading = true;
      isPaused = false;
      currentVerseIndex = 0;
    });
    _readVerse(0);
  }

  void _readVerse(int index) async {
    final verses = _chapterContents[widget.chapterId];
    if (verses == null || verses.isEmpty) return;

    if (index >= verses.length) {
      _fetchNextChapter();
      return;
    }

    if (index == 0) {
      await _announceChapter(chapterName);
    }

    final text = verses[index]['text'] ?? '';
    if (text.trim().isEmpty) {
      _readNextVerse();
      return;
    }

    setState(() => currentVerseIndex = index);
    await flutterTts.speak(text);
  }

  void _readNextVerse() {
    final verses = _chapterContents[widget.chapterId];
    if (verses == null || verses.isEmpty) return;

    final newIndex = currentVerseIndex != null ? currentVerseIndex! + 1 : 0;
    if (newIndex < verses.length) {
      _readVerse(newIndex);
    } else {
      _fetchNextChapter();
    }
  }

  void _pauseReading() {
    flutterTts.stop();
    setState(() {
      isReading = false;
      isPaused = true;
    });
  }

  void _resumeReading() {
    final index = currentVerseIndex != null ? currentVerseIndex! : 0;
    setState(() {
      isReading = true;
      isPaused = false;
    });
    _readVerse(index);
  }

  void _skipReading() {
    flutterTts.stop();
    setState(() => isSkipping = true);
    _readNextVerse();
  }

  Future<void> _announceChapter(String chapterName) async {
    setState(() => isSkipping = true);
    await flutterTts.speak(chapterName);
  }

  Future<void> _fetchNextChapter() async {
    int currentIndex = widget.chapterIds.indexOf(widget.chapterId);
    if (currentIndex < 0) return;

    final nextIndex = currentIndex + 1;
    if (nextIndex >= widget.chapterIds.length) {
      setState(() => isReading = false);
      return;
    }

    final nextChapterId = widget.chapterIds[nextIndex];
    final nextChapterName = widget.chapterNames[nextIndex];

    await _fetchChapterContent(nextChapterId);

    setState(() {
      widget.chapterId = nextChapterId;
      chapterName = nextChapterName;
      currentVerseIndex = 0;
      _pageController.jumpToPage(nextIndex);
      isSkipping = false;
    });

    _readVerse(0);
  }

  // Existing method for left/right arrow navigation
  void _changePage(int direction) async {
    setState(() {
      isLoading = true;
      pageChanging = true;
    });
    if (direction == -1 && currentPageIndex > 0) {
      currentPageIndex--;
    } else if (direction == 1 &&
        currentPageIndex < widget.chapterIds.length - 1) {
      currentPageIndex++;
    } else {
      setState(() {
        isLoading = false;
        pageChanging = false;
      });
      return;
    }

    _changeToChapter(currentPageIndex);
  }

  void _changeToChapter(int index) async {
    if (index < 0 || index >= widget.chapterIds.length) return;

    final newChapterId = widget.chapterIds[index];
    final newChapterName = widget.chapterNames[index];

    if (isReading) {
      flutterTts.stop();
    }

    setState(() {
      widget.chapterId = newChapterId;
      chapterName = newChapterName;
      currentVerseIndex = 0;
      currentPageIndex = index;
      isLoading = true;
    });

    await _fetchChapterContent(newChapterId);
    _pageController.jumpToPage(index);

    if (isReading) {
      _resumeReading();
    }
  }

  void _showChapterSelection() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        final theme = Theme.of(context);
        return Container(
          color: theme.scaffoldBackgroundColor,
          child: ListView.builder(
            itemCount: widget.chapterNames.length,
            itemBuilder: (context, index) {
              return ListTile(
                title: Text(widget.chapterNames[index]),
                onTap: () {
                  Navigator.of(context).pop(); // close bottom sheet
                  _changeToChapter(index);
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _preloadAdjacentChapters(String chapterId) async {
    if (_lastPreloadedChapterId == chapterId) return;
    _lastPreloadedChapterId = chapterId;

    final index = widget.chapterIds.indexOf(chapterId);
    final idsToPreload = [
      if (index - 2 >= 0) widget.chapterIds[index - 2],
      if (index - 1 >= 0) widget.chapterIds[index - 1],
      if (index + 1 < widget.chapterIds.length) widget.chapterIds[index + 1],
      if (index + 2 < widget.chapterIds.length) widget.chapterIds[index + 2],
    ];

    for (final id in idsToPreload) {
      if (!_chapterContents.containsKey(id)) {
        // Don't block, don't show spinner
        unawaited(_fetchChapterContent(id, showLoading: false));
      }
    }
  }

  void _summarizeContent() {
    final selectedTexts = highlightKey.currentState?.getSelectedTexts() ?? [];

    final contentToSummarize = selectedTexts.isNotEmpty
        ? selectedTexts.join(' ')
        : (_chapterContents[widget.chapterId] ?? [])
            .map((v) => v['text'])
            .join(' ');

    final prompt =
        "Summarize and provide context and interpretations for the following verses:\n$contentToSummarize";

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, __, ___) => StreamedSummaryModal(prompt: prompt),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: savedVersesActive
            ? null
            : AppBar(
                automaticallyImplyLeading: false,
                leading: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    IconButton(
                        iconSize: 24,
                        padding: const EdgeInsets.only(left: 12),
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () {
                          // Navigator.of(context).pushNamedAndRemoveUntil(
                          // '/main', (route) => false);
                          Navigator.of(context).pop();
                        })
                  ],
                ),
                toolbarHeight: 30,
                backgroundColor: theme.scaffoldBackgroundColor,
                iconTheme: IconThemeData(
                  color: (settingsProvider.currentThemeMode == ThemeMode.dark)
                      ? Colors.white
                      : Colors.black,
                ),
                actions: savedVersesActive
                    ? [
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              IconButton(
                                iconSize: 24,
                                padding: const EdgeInsets.only(left: 12),
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  setState(() => savedVersesActive = false);
                                  final currentIndex = widget.chapterIds
                                      .indexOf(widget.chapterId);
                                  if (_pageController.hasClients &&
                                      currentIndex !=
                                          _pageController.page?.round()) {
                                    _pageController.jumpToPage(currentIndex);
                                  }
                                },
                              ),
                            ],
                          ),
                        )
                      ]
                    : [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 14.0),
                            child: Center(
                              child: SizedBox(
                                height: 36,
                                child: Center(
                                  child: Text(
                                    widget.bookName,
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          color: (settingsProvider.currentThemeMode ==
                                  ThemeMode.dark)
                              ? Colors.white
                              : Colors.black,
                          icon: Icon(isReading ? Icons.stop : Icons.play_arrow),
                          onPressed: () {
                            if (isReading) {
                              _pauseReading();
                            } else {
                              _startReading();
                            }
                          },
                        ),
                      ],
              ),
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Stack(
          children: [
            Column(
              children: [
                // PageView for chapters
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: widget.chapterIds.length,
                    onPageChanged: (index) {
                      if (isReading) {
                        flutterTts.stop();
                      }
                      final newChapterId = widget.chapterIds[index];
                      final newChapterName = widget.chapterNames[index];

                      setState(() {
                        currentPageIndex = index;
                        widget.chapterId = newChapterId;
                        chapterName = newChapterName;
                        isReading
                            ? currentVerseIndex = 0
                            : currentVerseIndex = null;
                        isLoading = true;
                      });
                      _fetchChapterContent(newChapterId).then((_) {
                        _preloadAdjacentChapters(newChapterId);
                        setState(() {
                          isLoading = false;
                          pageChanging = false;
                        });
                        if (isReading) {
                          _resumeReading();
                        }
                      });
                    },
                    itemBuilder: (context, index) {
                      final chapterId = widget.chapterIds[index];
                      final verses = _chapterContents[chapterId] ?? [];
                      final isCurrent = chapterId == widget.chapterId;
                      if (verses.isEmpty) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      return SelectableTextHighlight(
                        loggedIn: settingsProvider.isLoggedIn,
                        key: isCurrent ? highlightKey : null,
                        chapterId: chapterId,
                        bookName: widget.bookName,
                        translationId:
                            settingsProvider.currentTranslationId ?? "",
                        verses: verses,
                        style:
                            theme.textTheme.bodyMedium!.copyWith(fontSize: 20),
                        currentVerseIndex: (chapterId == widget.chapterId)
                            ? currentVerseIndex
                            : -1,
                      );
                    },
                  ),
                ),

                if (isReading)
                  Container(
                    color: Colors.grey[200],
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.pause),
                          onPressed: _pauseReading,
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_next),
                          onPressed: _skipReading,
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            // Overlay: Saved Verses (only when active)
            if (savedVersesActive)
              Positioned.fill(
                child: Material(
                  color:
                      Colors.black.withOpacity(0.8), // Optional: dim background
                  child: Column(
                    children: [
                      AppBar(
                        backgroundColor:
                            Theme.of(context).scaffoldBackgroundColor,
                        leading: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            // IconButton(
                            //   iconSize: 24,
                            //   padding: const EdgeInsets.only(left: 12),
                            //   icon: const Icon(Icons.close),
                            //   onPressed: () {
                            //     setState(() => savedVersesActive = false);
                            //     final currentIndex =
                            //         widget.chapterIds.indexOf(widget.chapterId);
                            //     if (_pageController.hasClients &&
                            //         currentIndex !=
                            //             _pageController.page?.round()) {
                            //       _pageController.jumpToPage(currentIndex);
                            //     }
                            //   },
                            // ),
                          ],
                        ),
                        automaticallyImplyLeading: false,
                        title: const Text("Saved Verses"),
                        actions: [],
                      ),
                      Expanded(child: SavedVersesScreen()),
                    ],
                  ),
                ),
              ),

            if (isSummaryLoading)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
        bottomNavigationBar: !savedVersesActive
            ? BottomAppBar(
                color: theme.scaffoldBackgroundColor,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: <Widget>[
                    // Saved Verses
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (settingsProvider.isLoggedIn)
                          IconButton(
                            icon: const Icon(Icons.bookmark_add),
                            onPressed: () async {
                              final prefs =
                                  await SharedPreferences.getInstance();
                              final token = prefs.getString('token');
                              final settingsProvider =
                                  Provider.of<SettingsProvider>(context,
                                      listen: false);
                              final response = await http.post(
                                Uri.parse('https://api.bybl.dev/api/bookmarks'),
                                headers: {
                                  'Content-Type': 'application/json',
                                  'Authorization': 'Bearer ${token}',
                                },
                                body: json.encode({
                                  "chapter_id": widget.chapterId,
                                  "book_name": widget.bookName,
                                  "chapter_name": chapterName,
                                  "translation_id":
                                      settingsProvider.currentTranslationId,
                                }),
                              );

                              if (response.statusCode == 200) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Bookmark saved')),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Failed to save bookmark')),
                                );
                              }
                            },
                            tooltip: 'Bookmark',
                          ),
                        if (settingsProvider.isLoggedIn)
                          const Text('Bookmark',
                              style: TextStyle(fontSize: 12)),
                      ],
                    ),

                    IconButton(
                      icon: const Icon(Icons.arrow_circle_left, size: 40),
                      onPressed: () => _changePage(-1),
                    ),

                    InkWell(
                      onTap: _showChapterSelection,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          chapterName,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),

                    IconButton(
                      icon: const Icon(Icons.arrow_circle_right, size: 40),
                      onPressed: () => _changePage(1),
                    ),

                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (settingsProvider.isLoggedIn)
                          IconButton(
                            icon: const Icon(Icons.summarize),
                            onPressed: _summarizeContent,
                            tooltip: 'Summarize',
                          ),
                        if (settingsProvider.isLoggedIn)
                          const Text('Summarize',
                              style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              )
            : null,
      ),
    );
  }
}

class SummaryModal extends StatelessWidget {
  final String content;

  const SummaryModal({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Summary'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: MarkdownBody(data: content),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class StreamedSummaryModal extends StatefulWidget {
  final String prompt;

  const StreamedSummaryModal({super.key, required this.prompt});

  @override
  State<StreamedSummaryModal> createState() => _StreamedSummaryModalState();
}

class _StreamedSummaryModalState extends State<StreamedSummaryModal> {
  final StringBuffer _buffer = StringBuffer();
  late final StreamController<String> _controller;
  late final ChatService _chatService;
  StreamSubscription<String>? _subscription;
  bool _isStreaming = true;

  @override
  void initState() {
    super.initState();
    _controller = StreamController<String>.broadcast();
    _chatService = ChatService();

    _subscription = _chatService.streamResponse(widget.prompt).listen(
      (chunk) {
        if (mounted) {
          setState(() => _isStreaming = false);
        }
        _buffer.write(chunk);
        if (!_controller.isClosed) {
          _controller.add(_buffer.toString());
        }
      },
      onDone: () {
        if (!_controller.isClosed) {
          _controller.add(_buffer.toString()); // 💥 force rebuild
        }

        _controller.close();
      },
      onError: (e) {
        if (!_controller.isClosed) {
          _controller.add("Error: $e");
        }
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    if (!_controller.isClosed) _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Summary'),
      content: SizedBox(
        width: double.maxFinite,
        child: StreamBuilder<String>(
          stream: _controller.stream,
          builder: (context, snapshot) {
            final text = snapshot.data ?? '';

            return Stack(
              children: [
                SingleChildScrollView(
                  child: Text(text),
                ),
                if (_isStreaming)
                  SizedBox(
                    height: 24,
                    child: Align(
                      child: SizedBox(
                          height: 24,
                          width: 24,
                          child:
                              const Center(child: CircularProgressIndicator())),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
