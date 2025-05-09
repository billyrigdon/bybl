import 'dart:convert';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VerseProvider with ChangeNotifier {
  List<dynamic> publicVerses = [];
  List<dynamic> savedVerses = [];
  Map<int, int> likesCount = {};
  Map<int, int> commentCount = {};
  bool isLoading = false;
  String? _token;
  bool _hasMorePublicVerses = true;
  bool hasMoreSavedVerses = true;
  int _publicVersesPage = 1;
  int _savedVersesPage = 1;
  final int _pageSize = 10;
  bool isIniting = true;
  VerseProvider() {}

  Future<void> init() async {
    isIniting = true;
    notifyListeners();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');

    if (_token != null && (_token?.isNotEmpty ?? false)) {
      await fetchPublicVerses(reset: true);
      await fetchSavedVerses(reset: true);
    }

    isIniting = false;
    notifyListeners();
  }

  void reset() {
    publicVerses = [];
    savedVerses = [];
    likesCount = {};
    commentCount = {};
    isLoading = false;
    _token = null;
    _hasMorePublicVerses = true;
    hasMoreSavedVerses = true;
    _publicVersesPage = 1;
    _savedVersesPage = 1;
  }

// --- VerseProvider.dart -----------------------------------------------
  Future<void> fetchPublicVerses(
      {bool reset = false, bool init = false, silent = false}) async {
    if (_token == null || (isLoading && !reset)) return;

    if (reset) {
      publicVerses.clear();
      _publicVersesPage = 1;
      _hasMorePublicVerses = true;
      likesCount.clear();
      commentCount.clear();
    }
    if (!_hasMorePublicVerses) return;

    if (!silent) isLoading = true; // ← only when we want our own spinner
    if (init) isIniting = true;
    if (!silent) notifyListeners();

    final uri = Uri.parse(
      'https://api.bybl.dev/api/verses/public'
      '?page=$_publicVersesPage&pageSize=$_pageSize',
    );
    final res = await http.get(uri, headers: _authHeader);

    if (res.statusCode == 200) {
      final List<dynamic> newVerses = json.decode(res.body) ?? [];
      // publicVerses.addAll(newVerses);
      // final newVerses = json.decode(res.body) ?? [];
      for (var verse in newVerses) {
        print(verse);
        publicVerses.add({
          'UserVerseID': verse['user_verse_id'],
          'VerseID': verse['verse_id'],
          'Content': verse['content'],
          'Note': verse['note'],
          'is_published': verse['is_published'],
          'likes_count': verse['likes_count'],
          'comment_count': verse['comment_count'],
        });
      }

      _hasMorePublicVerses = newVerses.length == _pageSize;
      _publicVersesPage++;
    } else {
      debugPrint('Public fetch: ${res.statusCode} ${res.body}');
    }

    if (init) isIniting = false;
    isLoading = false;
    notifyListeners();
  }

  Map<String, String> get _authHeader => {
        'Authorization': 'Bearer $_token',
      };

  Future<void> saveVerse(String verseId, String text,
      {String note = ''}) async {
    if (_token == null) return;

    // Check if the verse is already saved.
    if (savedVerses.any((verse) => verse['VerseID'] == verseId)) {
      return;
    }

    // Add the verse to savedVerses before making the HTTP call.
    final verseEntry = {
      'UserVerseID': 0, // Placeholder, will be updated upon success.
      'VerseID': verseId,
      'Content': text,
      'Note': note,
    };

    savedVerses.add(verseEntry);
    notifyListeners();

    final verseData = {
      'VerseID': verseId,
      'Content': text,
      'Note': note,
    };

    try {
      final response = await http.post(
        Uri.parse('https://api.bybl.dev/api/verses/save'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
        body: json.encode(verseData),
      );

      if (response.statusCode == 200) {
        final responseBody = json.decode(response.body);
        final userVerseID = responseBody['userVerseID'];

        // Update the saved verse with the actual userVerseID.
        verseEntry['UserVerseID'] = userVerseID;
        notifyListeners();
      } else {
        // If the request fails, remove the verse from savedVerses.
        savedVerses.removeWhere((verse) => verse['VerseID'] == verseId);
        notifyListeners();
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack);
      savedVerses.removeWhere((verse) => verse['VerseID'] == verseId);
      notifyListeners();
    }
  }

  bool isVerseSaved(String verseId) {
    return savedVerses.any((verse) => verse['VerseID'] == verseId);
  }

  Future<dynamic> getVerseByUserVerseId(String userVerseId) async {
    final response = await http.get(
      Uri.parse('https://api.bybl.dev/api/verse/$userVerseId'),
      headers: {
        'Authorization': 'Bearer $_token',
      },
    );

    return json.decode(response.body);
  }

  String? getSavedVerseUserVerseID(String verseId) {
    final savedVerse = savedVerses.firstWhere(
      (verse) => verse['VerseID'] == verseId,
      orElse: () => null,
    );
    return savedVerse?['UserVerseID'].toString();
  }

  Future<void> fetchSavedVerses(
      {bool reset = false, bool loading = true}) async {
    if (_token == null) return;

    if (reset) {
      savedVerses = [];
      _savedVersesPage = 1;
      hasMoreSavedVerses = true;
    }

    if (isLoading || !hasMoreSavedVerses) return;

    if (loading) isLoading = true;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse(
          'https://api.bybl.dev/api/verses/saved?page=1&pageSize=200',
        ),
        headers: _authHeader,
      );

      if (response.statusCode == 200) {
        List<dynamic> newVerses = json.decode(response.body) ?? [];

        if (newVerses.length < _pageSize) {
          hasMoreSavedVerses = false;
        }

        _addSavedVersesWithoutDuplicates(newVerses);

        _savedVersesPage++;
      } else {
        debugPrint('Failed to fetch saved verses: ${response.statusCode}');
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // void _addSavedVersesWithoutDuplicates(List<dynamic> newVerses) {
  //   final existingIds = savedVerses.map((v) => v['UserVerseID']).toSet();

  //   for (var verse in newVerses) {
  //     if (!existingIds.contains(verse['UserVerseID'])) {
  //       savedVerses.add({
  //         'UserVerseID': verse['user_verse_id'],
  //         'VerseID': verse['verse_id'],
  //         'Content': verse['content'],
  //         'Note': verse['note'],
  //         'is_published': verse['is_published'],
  //         'likes_count': verse['likes_count'],
  //         'comment_count': verse['comment_count'],
  //       });
  //     }
  //   }
  // }

  void _addSavedVersesWithoutDuplicates(List<dynamic> newVerses) {
    final existingIds = savedVerses.map((v) => v['UserVerseID']).toSet();

    for (var verse in newVerses) {
      final newId = verse['user_verse_id'];
      if (!existingIds.contains(newId)) {
        savedVerses.add({
          'UserVerseID': newId,
          'VerseID': verse['verse_id'],
          'Content': verse['content'],
          'Note': verse['note'],
          'is_published': verse['is_published'],
          'likes_count': verse['likes_count'],
          'comment_count': verse['comment_count'],
        });
      }
    }
  }

// 1.  _getLikesCount / _getCommentCount:  **NO notifyListeners here**
  Future<void> _getLikesCount(int id) async {
    final res = await http.get(
      Uri.parse('https://api.bybl.dev/api/verse/$id/likes'),
      headers: _authHeader,
    );
    if (res.statusCode == 200) {
      likesCount[id] = json.decode(res.body)['likes_count'];
    }
  }

  Future<void> _getCommentCount(int id) async {
    final res = await http.get(
      Uri.parse('https://api.bybl.dev/api/verse/$id/comments/count'),
      headers: _authHeader,
    );
    if (res.statusCode == 200) {
      commentCount[id] = json.decode(res.body)['comment_count'];
    }
  }

  Future<void> toggleLike(int userVerseId) async {
    if (_token == null) return;

    final response = await http.post(
      Uri.parse('https://api.bybl.dev/api/verse/$userVerseId/toggle-like'),
      headers: _authHeader,
    );

    if (response.statusCode == 200) {
      // Instead of manually updating fields
      await refreshPublicVersesInPlace();
    } else {
      debugPrint('Failed to toggle like: ${response.statusCode}');
    }
  }

  Future<void> refreshPublicVersesInPlace() async {
    if (_token == null) return;

    // Figure out how many verses are already loaded
    final loadedCount = publicVerses.length;
    final pageSize = loadedCount == 0 ? _pageSize : loadedCount;

    final uri = Uri.parse(
      'https://api.bybl.dev/api/verses/public?page=1&pageSize=$pageSize',
    );

    final res = await http.get(uri, headers: _authHeader);

    if (res.statusCode == 200) {
      final List<dynamic> newVerses = json.decode(res.body) ?? [];

      if (newVerses.isNotEmpty) {
        publicVerses = newVerses
            .map((verse) => {
                  'UserVerseID': verse['user_verse_id'],
                  'VerseID': verse['verse_id'],
                  'Content': verse['content'],
                  'Note': verse['note'],
                  'is_published': verse['is_published'],
                  'likes_count': verse['likes_count'],
                  'comment_count': verse['comment_count'],
                  'username': verse['username'] ?? '',
                })
            .toList();

        notifyListeners();
      }
    } else {
      debugPrint('Failed to refresh public verses silently: ${res.statusCode}');
    }
  }

  Future<void> unsaveVerse(String userVerseId) async {
    final response = await http.delete(
      Uri.parse('https://api.bybl.dev/api/verses/$userVerseId'),
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      savedVerses.removeWhere(
          (verse) => verse['UserVerseID'] == int.parse(userVerseId));
      fetchSavedVerses(reset: false);
      fetchPublicVerses(reset: true);
      notifyListeners();
    }
  }

  Future<void> saveNote(String verseId, String userVerseId, String note) async {
    final existingVerse = savedVerses.firstWhere(
      (element) => element['UserVerseID'].toString() == userVerseId,
      orElse: () => null,
    );

    if (existingVerse == null) {
      return;
    }

    final response = await http.put(
      Uri.parse('https://api.bybl.dev/api/verses/$userVerseId'),
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      },
      body: json.encode({'note': note}),
    );

    if (response.statusCode == 200) {
      existingVerse['Note'] = note;
      notifyListeners();
    }
  }

  void updateVersePublishStatus(int userVerseId, bool isPublished) {
    final index =
        savedVerses.indexWhere((verse) => verse['UserVerseID'] == userVerseId);
    if (index != -1) {
      savedVerses[index]['is_published'] = isPublished;
      notifyListeners();
    }
  }

  Future<bool> publishVerse(String userVerseId) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.bybl.dev/api/verse/$userVerseId/publish'),
        headers: <String, String>{
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(<String, bool>{
          'is_published': true,
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        updateVersePublishStatus(int.parse(userVerseId), true); // <- Add this
        return true;
      } else {
        return false;
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack);
      return false;
    }
  }

  Future<bool> unpublishVerse(String userVerseId) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.bybl.dev/api/verse/$userVerseId/unpublish'),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode(<String, bool>{
          'is_published': false,
        }),
      );

      if (response.statusCode == 200) {
        updateVersePublishStatus(int.parse(userVerseId), false); // <- Add this
        return true;
      } else {
        return false;
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack);
      return false;
    }
  }

  Future<void> searchSavedVerses(String query, {bool reset = false}) async {
    if (_token == null || isLoading) return;

    if (reset) {
      savedVerses = [];
      _savedVersesPage = 1;
      hasMoreSavedVerses = true;
    }

    isLoading = true;
    notifyListeners();

    final response = await http.get(
      Uri.parse(
          'https://api.bybl.dev/api/verses/saved/search?q=$query&page=$_savedVersesPage&pageSize=$_pageSize'),
      headers: {
        'Authorization': 'Bearer $_token',
      },
    );

    if (response.statusCode == 200) {
      List<dynamic> newVerses = json.decode(response.body) ?? [];
      if (newVerses.length < _pageSize) {
        hasMoreSavedVerses = false;
      }
      _addSavedVersesWithoutDuplicates(newVerses);
      _savedVersesPage++;

      notifyListeners();
    } else {
      // Handle the error response
      notifyListeners();
    }

    isLoading = false;
    notifyListeners();
  }

  Future<void> searchPublicVerses(String query, {bool reset = false}) async {
    if (_token == null || isLoading) return;

    if (true) {
      publicVerses = [];
      _publicVersesPage = 1;
      _hasMorePublicVerses = true;
    }

    isLoading = true;
    notifyListeners();

    final response = await http.get(
      Uri.parse(
          'https://api.bybl.dev/api/verses/public/search?q=$query&page=$_publicVersesPage&pageSize=$_pageSize'),
      headers: {
        'Authorization': 'Bearer $_token',
      },
    );

    if (response.statusCode == 200) {
      List<dynamic> newVerses = json.decode(response.body) ?? [];
      if (newVerses.length < _pageSize) {
        _hasMorePublicVerses = false;
      }
      for (var verse in newVerses) {
        publicVerses.add({
          'UserVerseID': verse['user_verse_id'],
          'VerseID': verse['verse_id'],
          'Content': verse['content'],
          'Note': verse['note'],
          'is_published': verse['is_published'],
          'likes_count': verse['likes_count'],
          'comment_count': verse['comment_count'],
        });
      }

      _publicVersesPage++;
      for (var verse in newVerses) {
        int userVerseId = verse['UserVerseID'];
        _getLikesCount(userVerseId);
        _getCommentCount(userVerseId);
      }
      notifyListeners();
    } else {
      // Handle the error response
      notifyListeners();
    }

    isLoading = false;
    notifyListeners();
  }
}
