import 'dart:async';

import 'package:TheWord/main.dart';
import 'package:TheWord/providers/bible_provider.dart';
import 'package:TheWord/providers/friend_provider.dart';
import 'package:TheWord/providers/notification_provider.dart';
import 'package:TheWord/providers/verse_provider.dart';
import 'package:TheWord/screens/chat_screen.dart';
import 'package:TheWord/screens/notification_screen.dart';
import 'package:TheWord/screens/profile_screen.dart';
import 'package:TheWord/screens/public_verses.dart';
import 'package:TheWord/shared/widgets/loading_wrapper.dart';
import 'package:TheWord/shared/widgets/notifications_icon.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import 'book_list.dart';
import 'login_screen.dart';
import 'registration_screen.dart';
import 'saved_verses.dart';
import 'friend_list_screen.dart';
import 'settings_screen.dart';
import '../shared/widgets/dynamic_search_bar.dart';
import 'church_screen.dart';
import 'church_detail_screen.dart';
import '../providers/church_provider.dart';

//42 * 5
class MainAppScreen extends StatefulWidget {
  const MainAppScreen({Key? key}) : super(key: key);

  @override
  _MainAppScreenState createState() => _MainAppScreenState();
}

class _MainAppScreenState extends State<MainAppScreen> {
  int _currentIndex = 2;
  bool isInited = false;
  bool isInitRunning = false;
  // bool get _showSplash => isInitRunning || !isInited;

  late SettingsProvider settingsProvider;
  late FriendProvider friendProvider;
  late VerseProvider verseProvider;
  late ChurchProvider churchProvider;
  late BibleProvider bibleProvider;
  int notifications = 0;
  Timer? _timer;

  Future<void> init() async {
    setState(() {
      isInitRunning = true;
    });
    var settings = Provider.of<SettingsProvider>(context, listen: false);
    await settingsProvider.loadSettings();
    await bibleProvider
        .fetchBooks(settingsProvider.currentTranslationId ?? 'ESV');
    if (!settingsProvider.isLoggedIn) {
      setState(() {
        isInitRunning = false;
        isInited = false;
        return;
      });
    }
    settingsProvider.preloadUserAssets(context,
        'https://api.bybl.dev/api/avatar?type=user&id=${settingsProvider.userId}');
    verseProvider.init();
    await friendProvider.fetchFriends(context: context);
    await friendProvider.fetchSuggestedFriends(context: context);
    await churchProvider.fetchUserData();
    await churchProvider.fetchChurches(notify: false);
    await churchProvider.preloadAvatars(context);

    NotificationProvider notificationProvider =
        Provider.of<NotificationProvider>(context, listen: false);
    await notificationProvider.fetchAllNotifications();
    setState(() {
      isInited = true;
      isInitRunning = false;
      // notifications = notificationProvider.friendRequests.length +
      // notificationProvider.commentNotifications.length;
    });

    _startPeriodicNotificationFetch();
  }

  @override
  void initState() {
    super.initState();

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (notification != null && android != null) {
        flutterLocalNotificationsPlugin.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              'high_importance_channel',
              'High Importance Notifications',
              icon: '@mipmap/ic_launcher',
            ),
          ),
          payload: 'notifications', // Pass this so we can redirect later
        );
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      this._currentIndex = 4;
    });

    // For when app is terminated and launched from a notification
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        this._currentIndex = 4;
      }
    });

    friendProvider = Provider.of<FriendProvider>(context, listen: false);
    verseProvider = Provider.of<VerseProvider>(context, listen: false);
    churchProvider = Provider.of<ChurchProvider>(context, listen: false);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await init();
    });
  }

  @override
  void dispose() {
    // _timer?.cancel()?;
    super.dispose();
  }

  void _startPeriodicNotificationFetch() {
    if (_timer != null || !settingsProvider.isLoggedIn) {
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 30), (Timer t) async {
      if (!settingsProvider.isLoggedIn) {
        _timer?.cancel();
        return;
      }
 
      NotificationProvider notificationProvider =
          Provider.of<NotificationProvider>(context, listen: false);
      await notificationProvider.fetchAllNotifications();
      setState(() {
        notifications = notificationProvider.friendRequests.length +
            notificationProvider.commentNotifications.length;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    friendProvider = Provider.of<FriendProvider>(context, listen: false);
    verseProvider = Provider.of<VerseProvider>(context, listen: false);
    churchProvider = Provider.of<ChurchProvider>(context);
    settingsProvider = Provider.of<SettingsProvider>(context);
    bibleProvider = Provider.of<BibleProvider>(context);
    if (settingsProvider.isLoggedIn &&
        isInited == false &&
        isInitRunning == false) {
      init();
    }

    // Get current color from settings
    MaterialColor? currentColor = settingsProvider.currentColor;
    Color? fontColor = settingsProvider.currentThemeMode == ThemeMode.dark
        ? Colors.white
        : Colors.black;
    if (currentColor != null) {
      fontColor = settingsProvider.getFontColor(currentColor);
    }

    // Define the screens associated with each index
    // Define the screens associated with each index
    final List<Widget> _screens = [
      const ChurchScreen(), // 0 – Churches
      LoadingWrapper<VerseProvider>(
        isLoading: (provider) => provider.isIniting,
        child: PublicVersesScreen(),
      ), // 1 – Explore
      const BookListScreen(), // 2 – Bible
      ChatScreen(), // 3 – Ask Archie
      NotificationScreen(), // 4 – Notifications
    ];

    if (settingsProvider.loading ||
        (Provider.of<BibleProvider>(context).isLoadingBooks)) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return WillPopScope(
      onWillPop: () async {
        return false;
      },
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(60),
          child: AppBar(
            backgroundColor: currentColor,
            automaticallyImplyLeading: false,
            flexibleSpace: SafeArea(
              child: Container(
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        child: FixedAssetIcon(
                          'assets/icon/cross_nav.png',
                          color: fontColor,
                        ),
                      ),
                      if (_currentIndex == 2)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 14.0),
                            child: SizedBox(
                              height: 36,
                              child: DynamicSearchBar(
                                searchType: SearchType
                                    .BibleBooks, // Choose the appropriate search type
                                fontColor: fontColor,
                              ),
                            ),
                          ),
                        ),
                      if (_currentIndex == 1)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 14.0),
                            child: SizedBox(
                              height: 36,
                              child: DynamicSearchBar(
                                searchType: SearchType
                                    .PublicVerses, // Choose the appropriate search type
                                fontColor: fontColor,
                              ),
                            ),
                          ),
                        ),
                      if (_currentIndex == 4)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 14.0),
                            child: Center(
                              child: SizedBox(
                                height: 36,
                                child: Center(
                                  child: Text(
                                    'Notifications',
                                    style: TextStyle(
                                        color: settingsProvider.fontColor,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_currentIndex == 3)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 14.0),
                            child: Center(
                              child: SizedBox(
                                height: 36,
                                child: Center(
                                  child: Text(
                                    'Ask Archie',
                                    style: TextStyle(
                                        color: settingsProvider.fontColor,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_currentIndex == 0)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 14.0),
                            child: Center(
                              child: SizedBox(
                                height: 36,
                                child: Center(
                                  child: Text(
                                    'Churches',
                                    style: TextStyle(
                                        color: settingsProvider.fontColor,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Spacer(), // Add another spacer for even spacing
                      Row(
                        children: [
                          if (!settingsProvider.isLoggedIn)
                            IconButton(
                              color: fontColor,
                              icon: const Icon(Icons.login),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) => LoginScreen()),
                                );
                              },
                            ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment
                                  .center, // Aligns buttons centrally
                              children: [
                                if (settingsProvider.isLoggedIn)
                                  SizedBox(
                                    width:
                                        30, // Set a small width for the button container
                                    height:
                                        40, // Optional: Set height if needed
                                    child: IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints:
                                          BoxConstraints(), // Removes default constraints
                                      color: fontColor,
                                      icon: const Icon(Icons.person),
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                              builder: (context) =>
                                                  ProfileScreen()),
                                        );
                                      },
                                    ),
                                  ),
                                SizedBox(
                                    width:
                                        4), // Very small spacing between buttons
                                SizedBox(
                                  width:
                                      40, // Set a small width for the button container
                                  height: 40, // Optional: Set height if needed
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints:
                                        BoxConstraints(), // Removes default constraints
                                    color: fontColor,
                                    icon: const Icon(Icons.settings),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (context) =>
                                                SettingsScreen()),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          )
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        body: settingsProvider.isLoggedIn
            ? IndexedStack(
                index: _currentIndex,
                children: _screens,
              )
            : BookListScreen(), // Display only the BookListScreen if not logged in
        bottomNavigationBar: settingsProvider.isLoggedIn
            ? Theme(
                data: ThemeData(
                  canvasColor: currentColor, // Set canvasColor to currentColor
                ),
                child: BottomNavigationBar(
                  type: BottomNavigationBarType.fixed,
                  currentIndex: _currentIndex,
                  items: [
                    BottomNavigationBarItem(
                      // 0 – Churches
                      icon: Icon(Icons.church, color: fontColor),
                      label: 'Churches',
                    ),
                    BottomNavigationBarItem(
                      // 1 – Explore
                      icon: Icon(Icons.explore, color: fontColor),
                      label: 'Explore',
                    ),
                    BottomNavigationBarItem(
                      icon: ImageIcon(
                        const AssetImage('assets/icon/app_icon.png'),
                        size: 36,
                      ),
                      label: 'Bible',
                    ),
                    BottomNavigationBarItem(
                      // 3 – Ask Archie
                      icon: Icon(Icons.chat, color: fontColor),
                      label: 'Ask Archie',
                    ),
                    BottomNavigationBarItem(
                      // 4 – Notifications
                      icon: NotificationIcon(fontColor: fontColor),
                      label: 'Notifications',
                    ),
                  ],
                  selectedItemColor: _getContrastingTextColor(
                      currentColor ?? createMaterialColor(Colors.black)),
                  unselectedItemColor: _getContrastingTextColor(
                          currentColor ?? createMaterialColor(Colors.black))
                      .withOpacity(0.6),
                  showUnselectedLabels: true,
                  onTap: (index) async {
                    if (index == 0) {
                      // Church tab
                      // if (churchProvider.isMember &&
                      //     churchProvider.userChurchId != null) {
                      //   // If user is a member, navigate to their church details
                      //   await churchProvider
                      //       .selectChurch(churchProvider.userChurchId!);
                      //   Navigator.push(
                      //     context,
                      //     MaterialPageRoute(
                      //       builder: (context) => const ChurchDetailScreen(),
                      //     ),
                      //   );
                      // } else {
                      // If not a member, show church list
                      setState(() {
                        _currentIndex = index;
                      });
                      // }
                    } else {
                      setState(() {
                        _currentIndex = index;
                      });
                    }
                  },
                ),
              )
            : null, // No bottom bar if not logged in
      ),
    );
  }

  // Function to get a contrasting text color
  Color _getContrastingTextColor(MaterialColor backgroundColor) {
    // Calculate brightness to determine if white or black text is more readable
    int brightnessValue = ((backgroundColor.red * 299) +
            (backgroundColor.green * 587) +
            (backgroundColor.blue * 114)) ~/
        1000; // Integer division
    return brightnessValue > 128 ? Colors.black : Colors.white;
  }

  MaterialColor createMaterialColor(Color color) {
    final strengths = <double>[.05];
    final swatch = <int, Color>{};

    final r = color.red, g = color.green, b = color.blue;

    for (int i = 1; i < 10; i++) {
      strengths.add(0.1 * i);
    }
    for (var strength in strengths) {
      final double ds = 0.5 - strength;
      swatch[(strength * 1000).round()] = Color.fromRGBO(
        r + ((ds < 0 ? r : (255 - r)) * ds).round(),
        g + ((ds < 0 ? g : (255 - g)) * ds).round(),
        b + ((ds < 0 ? b : (255 - b)) * ds).round(),
        1,
      );
    }
    return MaterialColor(color.value, swatch);
  }
}

/// Wrap every image in this.
class ResponsiveImage extends StatelessWidget {
  final String asset; // or network url
  final double max; // logical px
  const ResponsiveImage(this.asset, {this.max = 400});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final target = w < max ? w : max; // never grow past `max`
    return Image.asset(asset, width: target);
  }
}

class FixedAssetIcon extends StatelessWidget {
  final String asset;
  final double size; // logical px you used on mobile
  final Color? color;
  const FixedAssetIcon(
    this.asset, {
    this.size = 60,
    this.color,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: size,
      height: size,
      color: color,
      fit: BoxFit.contain,
    );
  }
}
