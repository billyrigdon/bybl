// import 'dart:convert';
// import 'package:TheWord/screens/reader_screen.dart';
// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;
// import 'package:provider/provider.dart';
// import 'package:shared_preferences/shared_preferences.dart';

// import '../providers/settings_provider.dart';

// class BookmarksScreen extends StatefulWidget {
//   const BookmarksScreen({super.key});

//   @override
//   State<BookmarksScreen> createState() => _BookmarksScreenState();
// }

// class _BookmarksScreenState extends State<BookmarksScreen> {
//   List<dynamic> _bookmarks = [];
//   bool _isLoading = true;

//   @override
//   void initState() {
//     super.initState();
//     _fetchBookmarks();
//   }

//   Future<void> _fetchBookmarks() async {
//     final settingsProvider =
//         Provider.of<SettingsProvider>(context, listen: false);
//     final pref = await SharedPreferences.getInstance();
//     final token = pref.getString('token');
//     final response = await http.get(
//       Uri.parse('https://api.bybl.dev/api/bookmarks'),
//       headers: {
//         'Authorization': 'Bearer ${token}',
//       },
//     );

//     if (response.statusCode == 200) {
//       setState(() {
//         _bookmarks = json.decode(response.body);
//         _isLoading = false;
//       });
//     } else {
//       setState(() => _isLoading = false);
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text('Failed to load bookmarks')),
//       );
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);

//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Bookmarks'),
//         backgroundColor: theme.scaffoldBackgroundColor,
//       ),
//       body: _isLoading
//           ? const Center(child: CircularProgressIndicator())
//           : _bookmarks.isEmpty
//               ? const Center(child: Text('No bookmarks found.'))
//               : ListView.builder(
//                   itemCount: _bookmarks.length,
//                   itemBuilder: (context, index) {
//                     final bookmark = _bookmarks[index];
//                     return ListTile(
//                       title: Text(
//                           '${bookmark["book_name"]} ${bookmark["chapter_name"]}'),
//                       subtitle: Text(bookmark["translation_id"]),
//                       onTap: () {
//                         Navigator.pop(context);
//                         Navigator.push(
//                           context,
//                           MaterialPageRoute(
//                             builder: (_) => ReaderScreen(
//                               chapterId: bookmark["chapter_id"],
//                               chapterName: bookmark["chapter_name"],
//                               chapterIds: [
//                                 bookmark["chapter_id"]
//                               ], // or a full list
//                               chapterNames: [bookmark["chapter_name"]],
//                               bookName: bookmark["book_name"],
//                             ),
//                           ),
//                         );
//                       },
//                     );
//                   },
//                 ),
//     );
//   }
// }
import 'dart:convert';
import 'package:TheWord/providers/bible_provider.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'reader_screen.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  Map<String, List<dynamic>> groupedBookmarks = {};
  bool _isLoading = false;
  String? _token;
  List<dynamic> chapters = [];
  @override
  void initState() {
    super.initState();
    _loadTokenAndFetch();
  }

  Future<void> _loadTokenAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in')),
      );
      return;
    }

    setState(() => _token = token);
    await _fetchBookmarks();
  }

  Future<void> _fetchBookmarks() async {
    if (_token == null) return;
    setState(() => _isLoading = true);

    final response = await http.get(
      Uri.parse('https://api.bybl.dev/api/bookmarks?page=1&pageSize=200'),
      headers: {'Authorization': 'Bearer $_token'},
    );

    if (response.statusCode == 200) {
      final bookmarks = json.decode(response.body);
      final sorted = _groupAndSort(bookmarks);
      setState(() => groupedBookmarks = sorted);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load bookmarks')),
      );
    }

    setState(() => _isLoading = false);
  }

  Future<List<dynamic>> fetchChapters(
      String translationId, String bookId) async {
    try {
      final response = await http.get(
        Uri.parse(
            'api.bybl.dev/api/bible/${translationId}/books/$bookId/chapters'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        List<dynamic> incomingChapters = data['data'];
        chapters = chapters.where((c) => c['number'] != 'intro').toList();

        return chapters;
      } else {
        throw Exception('Failed to load chapters');
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack);
      return [];
    }
  }

  Map<String, List<dynamic>> _groupAndSort(List<dynamic> bookmarks) {
    Map<String, List<dynamic>> groups = {};

    for (final b in bookmarks) {
      final bookName = b['book_name'] ?? 'Unknown';
      groups.putIfAbsent(bookName, () => []).add(b);
    }

    for (final list in groups.values) {
      list.sort((a, b) => _chapterNumber(a['chapter_name'])
          .compareTo(_chapterNumber(b['chapter_name'])));
    }

    final sortedKeys = groups.keys.toList()..sort();
    return {
      for (final k in sortedKeys) k: groups[k]!,
    };
  }

  int _chapterNumber(String chapterName) {
    final match = RegExp(r'\d+').firstMatch(chapterName);
    return match != null ? int.parse(match.group(0)!) : 0;
  }

  Future<void> _deleteBookmark(int bookmarkId) async {
    if (_token == null) return;

    final response = await http.delete(
      Uri.parse('https://api.bybl.dev/api/bookmarks/$bookmarkId'),
      headers: {'Authorization': 'Bearer $_token'},
    );

    if (response.statusCode == 200) {
      await _fetchBookmarks();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bookmark removed')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete bookmark')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bookmarks'),
        backgroundColor: theme.scaffoldBackgroundColor,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchBookmarks,
              child: groupedBookmarks.isEmpty
                  ? const Center(child: Text('No bookmarks'))
                  : ListView(
                      children: groupedBookmarks.entries
                          .expand((entry) => [
                                Padding(
                                  padding: const EdgeInsets.only(
                                      top: 16, left: 16, bottom: 4),
                                  child: Text(entry.key,
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold)),
                                ),
                                ...entry.value.map((book) => Card(
                                      margin: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      color: theme.cardColor.withOpacity(
                                          theme.brightness == Brightness.light
                                              ? 0.9
                                              : 1.0),
                                      child: ListTile(
                                        contentPadding:
                                            const EdgeInsets.all(12),
                                        title: Text(book['chapter_name']),
                                        trailing: IconButton(
                                          icon: const Icon(Icons.delete,
                                              color: Colors.redAccent),
                                          onPressed: () => _deleteBookmark(
                                              book['bookmark_id']),
                                        ),
                                        onTap: () async {
                                          List<dynamic> chapters =
                                              await fetchChapters(
                                                  book['translation_id'],
                                                  book['book_id']);
                                          Navigator.of(context)
                                              .push(MaterialPageRoute(
                                                  builder: (_) => ReaderScreen(
                                                        chapterId:
                                                            book['chapter_id'],
                                                        chapterName: book[
                                                            'chapter_name'],
                                                        chapterIds: chapters
                                                            .map((c) => c['id'])
                                                            .toList(),
                                                        chapterNames: chapters
                                                            .map((c) =>
                                                                'Chapter ${c['number']}')
                                                            .toList(),
                                                        bookName:
                                                            book['book_name'],
                                                        translationId: book[
                                                            'translation_id'],
                                                        translationName: book[
                                                            'translation_name'],
                                                      )));
                                        },
                                      ),
                                    ))
                              ])
                          .toList(),
                    ),
            ),
    );
  }
}
