import 'dart:convert';
import 'package:TheWord/screens/reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/settings_provider.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  List<dynamic> _bookmarks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchBookmarks();
  }

  Future<void> _fetchBookmarks() async {
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    final pref = await SharedPreferences.getInstance();
    final token = pref.getString('token');
    final response = await http.get(
      Uri.parse('https://api.bybl.dev/api/bookmarks'),
      headers: {
        'Authorization': 'Bearer ${token}',
      },
    );

    if (response.statusCode == 200) {
      setState(() {
        _bookmarks = json.decode(response.body);
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load bookmarks')),
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
          : _bookmarks.isEmpty
              ? const Center(child: Text('No bookmarks found.'))
              : ListView.builder(
                  itemCount: _bookmarks.length,
                  itemBuilder: (context, index) {
                    final bookmark = _bookmarks[index];
                    return ListTile(
                      title: Text(
                          '${bookmark["book_name"]} ${bookmark["chapter_name"]}'),
                      subtitle: Text(bookmark["translation_id"]),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ReaderScreen(
                              chapterId: bookmark["chapter_id"],
                              chapterName: bookmark["chapter_name"],
                              chapterIds: [
                                bookmark["chapter_id"]
                              ], // or a full list
                              chapterNames: [bookmark["chapter_name"]],
                              bookName: bookmark["book_name"],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
