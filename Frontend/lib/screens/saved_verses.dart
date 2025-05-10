import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../providers/verse_provider.dart';
import '../shared/widgets/verse_card.dart';
import 'comment_screen.dart';

class SavedVersesScreen extends StatefulWidget {
  @override
  _SavedVersesScreenState createState() => _SavedVersesScreenState();
}

class _SavedVersesScreenState extends State<SavedVersesScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    final verseProvider = Provider.of<VerseProvider>(context, listen: false);
    verseProvider.fetchSavedVerses(reset: true); // Initial fetch
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final verseProvider = Provider.of<VerseProvider>(context, listen: false);
      verseProvider.fetchSavedVerses(); // Fetch more data
    }
  }

  Future<void> _onRefresh() async {
    final verseProvider = Provider.of<VerseProvider>(context, listen: false);
    await verseProvider.fetchSavedVerses(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VerseProvider>(
      builder: (context, verseProvider, child) {
        return Scaffold(
          body: verseProvider.savedVerses.isEmpty && !verseProvider.isLoading
              ? const Center(child: Text('No saved verses'))
              : RefreshIndicator(
                  onRefresh: _onRefresh,
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: verseProvider.savedVerses.length +
                        (verseProvider.hasMoreSavedVerses ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == verseProvider.savedVerses.length) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final verse = verseProvider.savedVerses[index];
                      int userVerseId = verse['UserVerseID'];
                      bool isPublished = verse['is_published'] ?? false;
                      return Dismissible(
                        key: Key(verse['VerseID'].toString()),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (direction) {
                          verseProvider.unsaveVerse(userVerseId.toString());
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Verse removed')),
                          );
                        },
                        child: VerseCard(
                          verseId: verse['VerseID'],
                          note: verse['Note'] ?? '',
                          verseContent: verse['Content'],
                          likesCount:
                              verseProvider.likesCount[userVerseId] ?? 0,
                          commentCount:
                              verseProvider.commentCount[userVerseId] ?? 0,
                          onLike: () {},
                          onComment: () => _navigateToComments(context, verse),
                          isSaved: true,
                          isPublished: isPublished,
                          onSaveNote: (note) async {
                            try {
                              await verseProvider.saveNote(
                                verse['VerseID'].toString(),
                                verse['UserVerseID'].toString(),
                                note,
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Verse saved successfully')),
                              );
                            } catch (e, stack) {
                              FirebaseCrashlytics.instance
                                  .recordError(e, stack);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Verse failed to save')),
                              );
                            }
                          },
                          onPublish: isPublished
                              ? null
                              : (note) => _publishVerse(
                                  context, verse["VerseID"], userVerseId, note),
                          onUnpublish: isPublished
                              ? () => _unpublishVerse(context, userVerseId)
                              : null,
                        ),
                      );
                    },
                  ),
                ),
        );
      },
    );
  }

  void _navigateToComments(BuildContext context, verse) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CommentsScreen(verse: verse)),
    );
  }

  Future<void> _publishVerse(
      BuildContext context, verseId, int userVerseId, String note) async {
    final verseProvider = Provider.of<VerseProvider>(context, listen: false);
    try {
      await verseProvider.saveNote(verseId, userVerseId.toString(), note);
      final success = await verseProvider.publishVerse(userVerseId.toString());
      if (success) {
        verseProvider.updateVersePublishStatus(userVerseId, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verse published successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to publish verse')),
        );
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save verse')),
      );
    }
  }

  Future<void> _unpublishVerse(BuildContext context, int userVerseId) async {
    final verseProvider = Provider.of<VerseProvider>(context, listen: false);
    final success = await verseProvider.unpublishVerse(userVerseId.toString());
    if (success) {
      verseProvider.updateVersePublishStatus(userVerseId, false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verse unpublished successfully')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to unpublish verse')),
      );
    }
  }
}
