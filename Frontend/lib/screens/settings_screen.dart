import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:string_similarity/string_similarity.dart';

import '../providers/bible_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/change_password_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ───────────────────────────────── UI CONTROLLERS ────────────────────────────
  late final TextEditingController _searchController;
  Timer? _debounce;

  // Data lists
  List<dynamic> _filteredTranslations = [];

  // ────────────────────────────── LIFECYCLE ────────────────────────────────────
  @override
  void initState() {
    super.initState();

    final bibleProvider = Provider.of<BibleProvider>(context, listen: false);
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);

    _searchController = TextEditingController(
        text: settingsProvider.currentTranslationName ?? '');
    _filteredTranslations = bibleProvider.translations;

    _searchController
        .addListener(() => _filterTranslations(_searchController.text));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ─────────────────────────────── HELPERS ────────────────────────────────────
  void _filterTranslations(String query) {
    final bibleProvider = Provider.of<BibleProvider>(context, listen: false);
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);

    setState(() {
      // Simple fuzzy + substring filter
      final all = bibleProvider.translations;
      if (query.isEmpty) {
        _filteredTranslations = all;
        return;
      }

      final lowerQuery = query.toLowerCase();
      // score each translation
      final scored = all.map((t) {
        final display = _buildDisplayName(t).toLowerCase();
        final score = StringSimilarity.compareTwoStrings(display, lowerQuery);
        return {...t, '_score': score};
      }).where((t) {
        // quick substring boost
        final disp = _buildDisplayName(t).toLowerCase();
        return disp.contains(lowerQuery) || t['_score'] > 0.2;
      }).toList();

      scored.sort(
          (a, b) => (b['_score'] as double).compareTo(a['_score'] as double));
      _filteredTranslations = scored;

      // ensure current translation stays visible
      final currentId = settingsProvider.currentTranslationId;
      if (currentId != null &&
          _filteredTranslations.every((t) => t['id'] != currentId)) {
        final current =
            all.firstWhere((t) => t['id'] == currentId, orElse: () => {});
        if (current.isNotEmpty) _filteredTranslations.insert(0, current);
      }
    });
  }

  void _queueSave() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final settingsProvider =
          Provider.of<SettingsProvider>(context, listen: false);
      if (settingsProvider.isLoggedIn) {
        await settingsProvider.updateUserSettingsOnBackend();
      }
    });
  }

  String _buildDisplayName(Map t) {
    final name = t['name']?.toString() ?? '';
    final lang = t['language']?['name']?.toString() ?? '';
    return lang.isEmpty ? name : '$name ($lang)';
  }

  Future<void> _deleteAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return;

    final response = await http.delete(
      Uri.parse('https://api.bybl.dev/api/user'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (!mounted) return;

    if (response.statusCode == 200) {
      await Provider.of<SettingsProvider>(context, listen: false).logout();
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete account: ${response.body}')),
      );
    }
  }

  // ────────────────────────────── BUILD ───────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final bibleProvider = Provider.of<BibleProvider>(context);

    final List<MaterialColor> palette = [
      createMutedMaterialColor(const Color.fromARGB(255, 145, 39, 32)),
      createMutedMaterialColor(const Color.fromARGB(255, 255, 94, 148)),
      createMutedMaterialColor(const Color.fromARGB(255, 159, 86, 179)),
      createMutedMaterialColor(const Color.fromARGB(255, 125, 105, 218)),
      createMutedMaterialColor(const Color.fromARGB(255, 83, 98, 181)),
      createMutedMaterialColor(const Color.fromARGB(255, 29, 107, 171)),
      createMutedMaterialColor(const Color.fromARGB(255, 73, 178, 192)),
      createMutedMaterialColor(const Color.fromARGB(255, 52, 185, 172)),
      createMutedMaterialColor(const Color.fromARGB(255, 23, 66, 25)),
      createMutedMaterialColor(const Color.fromARGB(255, 100, 186, 100)),
      createMutedMaterialColor(const Color.fromARGB(255, 210, 199, 101)),
      createMutedMaterialColor(const Color.fromARGB(255, 231, 153, 36)),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          // ── Bible translation ──────────────────────────────────────────────
          ExpansionTile(
            title: const Text('Bible Translation'),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search or scroll translations',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              Container(
                height: 320,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2)),
                  ],
                ),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: ListView.builder(
                    itemCount: _filteredTranslations.length,
                    itemBuilder: (context, idx) {
                      final t = _filteredTranslations[idx];
                      final isCurrent =
                          t['id'] == settingsProvider.currentTranslationId;
                      return ListTile(
                        title: Text(_buildDisplayName(t),
                            overflow: TextOverflow.ellipsis),
                        trailing: isCurrent
                            ? const Icon(Icons.check, color: Colors.green)
                            : null,
                        onTap: () async {
                          await settingsProvider.updateTranslation(
                              t['id'], t['name']);
                          _searchController.text = t['name'];
                          await bibleProvider.fetchBooks(t['id']);
                          _queueSave();
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),

          // ── Theme & Colors ─────────────────────────────────────────────────
          ExpansionTile(
            title: const Text('Theme & Colors'),
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16.0, top: 8),
                child: Text('App Color',
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
              _buildColorGrid(
                palette,
                settingsProvider.currentColor,
                (c) => settingsProvider.updateColor(c),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.only(left: 16.0, top: 8),
                child: Text('Highlighter Color',
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
              _buildColorGrid(
                palette,
                settingsProvider.highlightColor,
                (c) => settingsProvider.updateHighlightColor(c),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.only(left: 16.0),
                child: Text('Theme Mode',
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
              _buildThemeModeOption(
                  settingsProvider, ThemeMode.light, 'Light Mode'),
              _buildThemeModeOption(
                  settingsProvider, ThemeMode.dark, 'Dark Mode'),
              const SizedBox(height: 8),
            ],
          ),

          // ── Privacy ────────────────────────────────────────────────────────
          if (settingsProvider.isLoggedIn)
            ExpansionTile(
              title: const Text('Privacy Settings'),
              children: [
                SwitchListTile(
                  title: const Text('Private Profile'),
                  value: !settingsProvider.isPublicProfile,
                  onChanged: (val) {
                    settingsProvider.togglePublicProfile(!val);
                    _queueSave();
                  },
                ),
              ],
            ),

          // ── Account ───────────────────────────────────────────────────────
          if (settingsProvider.isLoggedIn)
            ExpansionTile(
              title: const Text('Account Settings'),
              children: [
                ListTile(
                  title: const Text('Change Password'),
                  leading: const Icon(Icons.lock_outline),
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ChangePasswordScreen()));
                  },
                ),
                ListTile(
                  title: const Text('Delete Account',
                      style: TextStyle(color: Colors.red)),
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete Account'),
                        content: const Text(
                            'Are you sure you want to permanently delete your account? This cannot be undone.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel')),
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Delete',
                                  style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                    if (confirm == true) await _deleteAccount();
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ────────────────────────── UI BUILD HELPERS ───────────────────────────────
  Widget _buildColorGrid(List<MaterialColor> colors, Color? selected,
      Function(MaterialColor) onTap) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: colors.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 6,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemBuilder: (context, idx) {
          final color = colors[idx];
          final isSelected = selected?.value == color.value;
          return GestureDetector(
            onTap: () {
              onTap(color);
              _queueSave();
            },
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: isSelected
                    ? Border.all(color: Colors.white, width: 3)
                    : null,
              ),
              child: isSelected
                  ? const Center(child: Icon(Icons.check, color: Colors.white))
                  : null,
            ),
          );
        },
      ),
    );
  }

  Widget _buildThemeModeOption(
      SettingsProvider sp, ThemeMode mode, String label) {
    return ListTile(
      title: Text(label),
      leading: Radio<ThemeMode>(
        value: mode,
        groupValue: sp.currentThemeMode,
        onChanged: (val) {
          if (val != null) {
            sp.updateThemeMode(val);
            _queueSave();
          }
        },
      ),
    );
  }

  // ─────────────────────────── COLOR HELPERS ────────────────────────────────

  /// Return a pastel / “muted” MaterialColor by blending the base colour
  /// toward white.  The larger the blendFactor, the paler the shade.
  ///
  /// e.g.  blendFactor 0.80  →  80 % white  +  20 % base colour.
  MaterialColor createMutedMaterialColor(Color base,
      {double blendFactor = 0.80}) {
    assert(blendFactor >= 0 && blendFactor <= 1);

    Color _blend(double t) => Color.lerp(base, Colors.white, blendFactor * t)!;

    return MaterialColor(base.value, {
      50: _blend(1.00),
      100: _blend(0.90),
      200: _blend(0.80),
      300: _blend(0.65),
      400: _blend(0.45),
      500: _blend(0.30),
      600: _blend(0.20),
      700: _blend(0.12),
      800: _blend(0.07),
      900: _blend(0.04),
    });
  }
}
