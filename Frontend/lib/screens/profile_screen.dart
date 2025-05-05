import 'package:TheWord/screens/main_app.dart';
import 'package:TheWord/screens/user_profile_screen.dart';
import 'package:TheWord/services/settings_service.dart';
import 'package:TheWord/shared/widgets/editable_avatar.dart';
import 'package:TheWord/shared/widgets/initial_avatar.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/friend_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/verse_provider.dart';
import '../shared/widgets/dynamic_search_bar.dart';
import '../shared/widgets/verse_card.dart';
import 'comment_screen.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _versesScrollController = ScrollController();
  Color? fontColor;
  // int _avatarTimestamp = DateTime.now().millisecondsSinceEpoch;

  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _versesScrollController.addListener(_onVersesScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<VerseProvider>(context, listen: false)
          .fetchSavedVerses(reset: true);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _versesScrollController.dispose();
    super.dispose();
  }

  void _onVersesScroll() {
    final verseProvider = Provider.of<VerseProvider>(context, listen: false);
    if (_versesScrollController.position.pixels >=
        _versesScrollController.position.maxScrollExtent - 200) {
      verseProvider.fetchSavedVerses();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final currentColor = settingsProvider.currentColor;
    final accentColor = settingsProvider.getFontColor(currentColor!);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "My Profile",
          style: TextStyle(color: settingsProvider.fontColor),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: settingsProvider.fontColor,
          unselectedLabelColor: settingsProvider.fontColor?.withOpacity(0.7),
          labelStyle:
              const TextStyle(fontSize: 12), // 👈 smaller font for active tab
          unselectedLabelStyle:
              const TextStyle(fontSize: 12), // 👈 smaller font for inactive tab
          tabs: const [
            Tab(text: 'Profile'),
            Tab(text: 'Highlights'),
            Tab(text: 'My Friends'),
            Tab(text: 'Suggested'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              Provider.of<FriendProvider>(context, listen: false).reset();
              Provider.of<VerseProvider>(context, listen: false).reset();
              await settingsProvider.logout();
              SharedPreferences prefs = await SharedPreferences.getInstance();
              prefs.clear();

              Navigator.of(context)
                  .pushNamedAndRemoveUntil('/main', (route) => false);
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildProfileTab(), // new
          Consumer<VerseProvider>(
            builder: (context, verseProvider, _) =>
                _buildSavedVersesTab(verseProvider),
          ),
          Consumer<FriendProvider>(
            builder: (context, friendProvider, _) =>
                _buildMyFriendsTab(friendProvider),
          ),
          Consumer<FriendProvider>(
            builder: (context, friendProvider, _) =>
                _buildSuggestedFriendsTab(friendProvider),
          ),
        ],
      ),
    );
  }

  // Future<void> _pickAndUploadAvatar() async {
  //   final picker = ImagePicker();
  //   final pickedFile = await picker.pickImage(source: ImageSource.gallery);

  //   if (pickedFile != null) {
  //     final request = http.MultipartRequest(
  //       'POST',
  //       Uri.parse('https://api.bybl.dev/api/user/avatar'),
  //     );
  //     final prefs = await SharedPreferences.getInstance();
  //     final token = prefs.getString('token');
  //     request.headers['Authorization'] = 'Bearer $token';
  //     request.files
  //         .add(await http.MultipartFile.fromPath('avatar', pickedFile.path));

  //     final response = await request.send();

  //     if (response.statusCode == 200) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         const SnackBar(content: Text('Profile picture updated!')),
  //       );
  //       await Provider.of<SettingsProvider>(context, listen: false)
  //           .fetchUserSettingsFromBackend(token!);
  //       setState(() {});
  //     } else {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(
  //             content:
  //                 Text('Failed to upload picture: ${response.reasonPhrase}')),
  //       );
  //     }
  //   }
  // }

  // Future<void> _pickAndUploadAvatar() async {
  //   final picker = ImagePicker();
  //   final pickedFile = await picker.pickImage(source: ImageSource.gallery);

  //   if (pickedFile != null) {
  //     final croppedFile = await ImageCropper().cropImage(
  //       sourcePath: pickedFile.path,
  //       // aspectRatioPresets: [
  //       // CropAspectRatioPreset.square,
  //       // ],
  //       uiSettings: [
  //         AndroidUiSettings(
  //           toolbarTitle: 'Crop Image',
  //           toolbarColor: Theme.of(context).primaryColor,
  //           toolbarWidgetColor: Colors.white,
  //           initAspectRatio: CropAspectRatioPreset.square,
  //           lockAspectRatio: true,
  //         ),
  //         IOSUiSettings(
  //           title: 'Crop Image',
  //           aspectRatioLockEnabled: true,
  //         ),
  //       ],
  //     );

  //     if (croppedFile != null) {
  //       final request = http.MultipartRequest(
  //         'POST',
  //         Uri.parse('https://api.bybl.dev/api/user/avatar'),
  //       );
  //       final prefs = await SharedPreferences.getInstance();
  //       final token = prefs.getString('token');
  //       request.headers['Authorization'] = 'Bearer $token';
  //       request.files
  //           .add(await http.MultipartFile.fromPath('avatar', croppedFile.path));

  //       final response = await request.send();

  //       if (response.statusCode == 200) {
  //         ScaffoldMessenger.of(context).showSnackBar(
  //           const SnackBar(content: Text('Profile picture updated!')),
  //         );
  //         await Provider.of<SettingsProvider>(context, listen: false)
  //             .fetchUserSettingsFromBackend(token!);

  //         setState(() {
  //           // Force refresh with timestamp to bust the cache
  //           _avatarUrl =
  //               'https://api.bybl.dev/api/avatar?type=user&id=${Provider.of<SettingsProvider>(context, listen: false).userId}&ts=${DateTime.now().millisecondsSinceEpoch}';
  //         });
  //       } else {
  //         ScaffoldMessenger.of(context).showSnackBar(
  //           SnackBar(
  //               content:
  //                   Text('Failed to upload picture: ${response.reasonPhrase}')),
  //         );
  //       }
  //     }
  //   }
  // }

  Widget _buildProfileTab() {
    final settingsProvider = Provider.of<SettingsProvider>(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          EditableAvatar(
            radius: 60,
            imageUrl: _avatarUrl ??
                'https://api.bybl.dev/api/avatar?type=user&id=${settingsProvider.userId}',
            fallbackIcon: Icons.person,
            // onEdit: () => SettingsService().handleAvatarUpload(
            //       context: context,
            //       uploadUrl: 'https://api.bybl.dev/api/user/avatar',
            //       onSuccess: () async {
            // final prefs = await SharedPreferences.getInstance();
            // final token = prefs.getString('token');

            // if (token != null) {
            //   final settingsProvider =
            //       Provider.of<SettingsProvider>(context, listen: false);
            //   await settingsProvider.fetchUserSettingsFromBackend(token);

            //   // ✅ AFTER upload, update your local URL with timestamp to bust cache
            //   setState(() {
            //     _avatarUrl =
            //         'https://api.bybl.dev/api/avatar?type=user&id=${settingsProvider.userId}&ts=${DateTime.now().millisecondsSinceEpoch}';
            //   });
            //         }
            //       }),
            onEdit: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CircularAvatarCropper(
                    onUploadSuccess: (newUrl) {
                      setState(() {
                        _avatarUrl = newUrl;
                      });
                    },
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 16),
          Divider(),
          ListTile(
            title: const Text('Username'),
            subtitle: Text(settingsProvider.username ?? 'Unknown'),
          ),
          // ListTile(
          // title: const Text('Email'),
          // subtitle: Text(settingsProvider.email ?? 'Unknown'),
          // ),
          // ListTile(
          // title: const Text('Public Profile'),
          // subtitle: Text(settingsProvider.isPublicProfile ? 'Yes' : 'No'),
          // ),
          ListTile(
            title: const Text('Preferred Translation'),
            subtitle: Text(settingsProvider.currentTranslationName ?? 'None'),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestedFriendsTab(FriendProvider friendProvider) {
    final notificationsProvider = Provider.of<NotificationProvider>(context);

    return RefreshIndicator(
      onRefresh: () async {
        await friendProvider.fetchSuggestedFriends();
      },
      child: ListView(
        padding: const EdgeInsets.all(8.0),
        children: [
          const Text('Suggested Friends',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          if (friendProvider.suggestedFriends.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text('No suggested friends at the moment.',
                  style: TextStyle(color: Colors.grey)),
            ),
          ...friendProvider.suggestedFriends.map((suggested) => ListTile(
                leading: CircleAvatar(
                  backgroundImage: suggested.avatarUrl != null &&
                          suggested.avatarUrl!.isNotEmpty
                      ? NetworkImage(
                          'https://api.bybl.dev/api/avatar?type=user&id=${suggested.userID}')
                      : null,
                  child: (suggested.avatarUrl == null ||
                          suggested.avatarUrl!.isEmpty)
                      ? InitialAvatar(username: suggested.username)
                      : null,
                ),
                title: Text(suggested.username),
                subtitle: Text('${suggested.mutualFriends} mutual friends'),
                trailing: ElevatedButton(
                  onPressed:
                      !notificationsProvider.isFriendRequested(suggested.userID)
                          ? () => notificationsProvider
                              .sendFriendRequest(suggested.userID)
                          : null,
                  child: Text(
                    notificationsProvider.isFriendRequested(suggested.userID)
                        ? 'Friend Request Sent'
                        : 'Add Friend',
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildMyFriendsTab(FriendProvider friendProvider) {
    return RefreshIndicator(
      onRefresh: () async {
        await friendProvider.fetchFriends();
      },
      child: ListView(
        padding: const EdgeInsets.all(8.0),
        children: [
          const Text('My Friends',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          if (friendProvider.friends.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text('You have no friends added yet.',
                  style: TextStyle(color: Colors.grey)),
            ),
          ...friendProvider.friends.map((friend) => ListTile(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          UserProfileScreen(userId: friend.userID),
                    ),
                  );
                },
                leading: CircleAvatar(
                  backgroundImage: friend.avatarUrl != null &&
                          friend.avatarUrl!.isNotEmpty
                      ? NetworkImage(
                          'https://api.bybl.dev/api/avatar?type=user&id=${friend.userID}')
                      : null,
                  child: (friend.avatarUrl == null || friend.avatarUrl!.isEmpty)
                      ? InitialAvatar(username: friend.username)
                      : null,
                ),
                title: Text(friend.username),
                subtitle: Text('${friend.mutualFriends} mutual friends'),
                trailing: ElevatedButton(
                  onPressed: () => friendProvider.removeFriend(friend.userID),
                  child: const Text('Remove'),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildSavedVersesTab(VerseProvider verseProvider) {
    return RefreshIndicator(
      onRefresh: () async {
        await verseProvider.fetchSavedVerses(reset: true);
      },
      child: verseProvider.savedVerses.isEmpty
          ? const Center(
              child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Text('No saved verses yet.',
                  style: TextStyle(color: Colors.grey)),
            ))
          : ListView.builder(
              controller: _versesScrollController,
              itemCount: verseProvider.savedVerses.length +
                  (verseProvider.hasMoreSavedVerses ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == verseProvider.savedVerses.length) {
                  return const Center(child: CircularProgressIndicator());
                }
                final verse = verseProvider.savedVerses[index];
                int userVerseId = verse['UserVerseID'];
                bool isPublished = verse['is_published'] ?? false;
                return VerseCard(
                  verseId: verse['VerseID'],
                  note: verse['Note'] ?? '',
                  verseContent: verse['Content'],
                  likesCount: verse['likes_count'] ?? 0,
                  commentCount: verse['comment_count'] ?? 0,
                  onLike: () {},
                  onComment: () => _navigateToComments(context, verse),
                  isSaved: true,
                  isPublished: isPublished,
                  onSaveNote: (note) async => await verseProvider.saveNote(
                    verse['VerseID'].toString(),
                    verse['UserVerseID'].toString(),
                    note,
                  ),
                  onDelete: () =>
                      verseProvider.unsaveVerse(userVerseId.toString()),
                  onPublish: isPublished
                      ? null
                      : (note) async => await verseProvider
                          .publishVerse(userVerseId.toString()),
                  onUnpublish: isPublished
                      ? () async => await verseProvider
                          .unpublishVerse(userVerseId.toString())
                      : null,
                );
              },
            ),
    );
  }

  void _navigateToComments(BuildContext context, dynamic verse) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CommentsScreen(verse: verse)),
    );
  }
}

class CircularAvatarCropper extends StatefulWidget {
  final Function(String newAvatarUrl) onUploadSuccess;

  const CircularAvatarCropper({super.key, required this.onUploadSuccess});

  @override
  State<CircularAvatarCropper> createState() => _CircularAvatarCropperState();
}

class _CircularAvatarCropperState extends State<CircularAvatarCropper> {
  final CropController _controller = CropController();
  Uint8List? _imageData;
  bool _isUploading = false;

  bool _showCropper = false;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final imageBytes = await picked.readAsBytes();
      setState(() {
        _imageData = imageBytes;
        _showCropper = true;
      });
    }
  }

  // Future<void> _uploadImage(Uint8List imageBytes) async {
  //   final uri = Uri.parse('https://api.bybl.dev/api/user/avatar');
  //   final request = http.MultipartRequest('POST', uri);

  //   final prefs = await SharedPreferences.getInstance();
  //   final token = prefs.getString('token');
  //   request.headers['Authorization'] = 'Bearer $token';

  //   request.files.add(
  //     http.MultipartFile.fromBytes('avatar', imageBytes,
  //         filename: 'avatar.jpg'),
  //   );

  //   final response = await request.send();
  //   if (response.statusCode == 200) {
  //     widget.onUploadSuccess(
  //       'https://api.bybl.dev/api/avatar?type=user&id=${prefs.getInt('userID')}&ts=${DateTime.now().millisecondsSinceEpoch}',
  //     );
  //     Navigator.of(context).pop(); // Close modal
  //   } else {
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(content: Text('Upload failed: ${response.reasonPhrase}')),
  //     );
  //   }
  // }

  Future<void> _uploadImage(Uint8List imageBytes) async {
    final uri = Uri.parse('https://api.bybl.dev/api/user/avatar');
    final request = http.MultipartRequest('POST', uri);

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final userId = Provider.of<SettingsProvider>(context, listen: false).userId;

    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(
      http.MultipartFile.fromBytes('avatar', imageBytes,
          filename: 'avatar.jpg'),
    );

    try {
      final response = await request.send();
      setState(() => _isUploading = false);

      if (response.statusCode == 200) {
        widget.onUploadSuccess(
          'https://api.bybl.dev/api/avatar?type=user&id=$userId&ts=${DateTime.now().millisecondsSinceEpoch}',
        );
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('token');

        if (token != null) {
          final settingsProvider =
              Provider.of<SettingsProvider>(context, listen: false);
          await settingsProvider.fetchUserSettingsFromBackend(token);
        }
        // ✅ AFTER upload, update your local URL with timestamp to bust cache
        // setState(() {
        // _avatarUrl =
        // 'https://api.bybl.dev/api/avatar?type=user&id=${settingsProvider.userId}&ts=${DateTime.now().millisecondsSinceEpoch}';
        // });
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: ${response.reasonPhrase}')),
        );
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack);
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _pickImage();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _imageData == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Center(
                  child: Crop(
                    controller: _controller,
                    image: _imageData!,
                    onCropped: (CropResult result) async {
                      if (result is CropSuccess) {
                        setState(() => _isUploading = true);
                        await _uploadImage(result.croppedImage);
                      } else if (result is CropFailure) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                                  Text('Cropping failed: ${result.cause}')),
                        );
                      }
                    },

                    withCircleUi: true,
                    // : 0.8,
                    baseColor: Colors.black,
                    maskColor: Colors.black54,
                    cornerDotBuilder: (size, edgeAlignment) =>
                        const DotControl(color: Colors.white),
                  ),
                ),
                Positioned(
                  bottom: 32,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: () {
                        _controller.crop();
                      },
                      child: const Text('Crop & Upload'),
                    ),
                  ),
                ),
                if (_isUploading)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
              ],
            ),
    );
  }
}
