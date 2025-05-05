import 'package:TheWord/firebase_options.dart';
import 'package:TheWord/providers/bible_provider.dart';
import 'package:TheWord/providers/friend_provider.dart';
import 'package:TheWord/providers/group_provider.dart';
import 'package:TheWord/providers/notification_provider.dart';
import 'package:TheWord/providers/settings_provider.dart';
import 'package:TheWord/providers/verse_provider.dart';
import 'package:TheWord/providers/church_provider.dart';
import 'package:TheWord/screens/main_app.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Handle background message if needed
  print('📩 Background Message: ${message.messageId}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  FirebaseMessaging.instance.getToken().then((token) {
    print("📲 FCM Token: $token");
  });

  // iOS: request permission
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  // Create a notification channel for Android
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    importance: Importance.high,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  const InitializationSettings initSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
  );

  await flutterLocalNotificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      // When the app is in background and tapped
      if (response.payload == 'notifications') {
        navigatorKey.currentState?.pushNamed('/main');
      }
    },
  );
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => SettingsProvider()),
        ChangeNotifierProvider(create: (context) => BibleProvider()),
        ChangeNotifierProvider(create: (context) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => FriendProvider()),
        ChangeNotifierProvider(create: (_) => VerseProvider()),
        ChangeNotifierProvider(create: (_) => ChurchProvider()),
        ChangeNotifierProvider(create: (_) => GroupProvider()),
      ],
      child: ByblApp(),
    ),
  );
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class ByblApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        BibleProvider bibleProvider =
            Provider.of<BibleProvider>(context, listen: false);
        bibleProvider.fetchTranslations();

        var themeFontColor = settings.currentThemeMode == ThemeMode.dark
            ? Colors.white
            : Colors.black;
        if (settings.currentColor != null)
          themeFontColor = settings.getFontColor(settings.currentColor!);

        return MaterialApp(
          initialRoute: '/main',
          routes: {
            '/main': (context) => const MainAppScreen(),
          },
          title: 'bybl',
          themeMode: settings.currentThemeMode,

          darkTheme: ThemeData(
            fontFamily: 'NotoSans',
            brightness: Brightness.dark,
            primarySwatch: settings.currentColor,
            scaffoldBackgroundColor: Colors.black,
            cardColor: Color(0xFF090909),
            textTheme: const TextTheme(
              bodyMedium: TextStyle(color: Colors.white),
            ),
            appBarTheme: AppBarTheme(
              foregroundColor: themeFontColor,
              backgroundColor: settings.currentColor,
              titleTextStyle: TextStyle(color: themeFontColor, fontSize: 20),
            ),
            bottomAppBarTheme: BottomAppBarTheme(
              surfaceTintColor: themeFontColor,
              color: settings.currentColor,
            ),
            listTileTheme: const ListTileThemeData(
              textColor: Colors.white,
              iconColor: Colors.white,
            ),
          ),
          theme: ThemeData(
            fontFamily: 'NotoSans',
            highlightColor: settings.highlightColor,
            brightness: Brightness.light,
            cardColor: Colors.white,
            primarySwatch: settings.currentColor,
            scaffoldBackgroundColor: Colors.white,
            textTheme: const TextTheme(
              bodyMedium: TextStyle(color: Colors.black),
            ),
            appBarTheme: AppBarTheme(
              foregroundColor: themeFontColor,
              backgroundColor: settings.currentColor,
              titleTextStyle: TextStyle(color: themeFontColor, fontSize: 20),
            ),
            bottomAppBarTheme: BottomAppBarTheme(
              surfaceTintColor: themeFontColor,
              color: settings.currentColor,
            ),
            listTileTheme: const ListTileThemeData(
              textColor: Colors.black,
              iconColor: Colors.black,
            ),
          ),
          // home: MainAppScreen(),
        );
      },
    );
  }
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
