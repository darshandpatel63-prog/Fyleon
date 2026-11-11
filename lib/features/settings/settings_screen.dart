import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../shared/widgets/animations.dart';
import '../files/application/browse_controller.dart';
import '../ads/native_ad_tile.dart';
import '../files/application/files_providers.dart';
import '../files/data/file_ops.dart';
import '../apps/apps_screen.dart';
import '../dash/dash_screens.dart';
import '../dash/dash_state.dart';
import '../viewer/viewer_prefs.dart';
import 'viewer_toolbar_screen.dart';
import '../samples/sample_generator.dart';
import 'themes_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    void soon(String what) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$what is coming in a later phase.')),
        );

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Text('Settings', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          ),
          _section(context, 'Appearance'),
          ListTile(
            leading: Icon(Icons.palette_rounded, color: scheme.primary),
            title: const Text('Themes'),
            subtitle: const Text('Free themes and premium themes'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(fadeSlideRoute(const ThemesScreen())),
          ),
          ListTile(
            leading: Icon(Icons.tune_rounded, color: scheme.primary),
            title: const Text('Viewer toolbar'),
            subtitle: const Text('Choose which buttons show directly: star, heart, share, edit...'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(fadeSlideRoute(const ViewerToolbarScreen())),
          ),
          const NativeAdTile(),
          _section(context, 'Tools'),
          ListTile(
            leading: Icon(Icons.bolt_rounded, color: scheme.primary),
            title: const Text(dashName),
            subtitle: const Text('Send files to nearby devices, no internet needed'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(fadeSlideRoute(const DashHomeScreen())),
          ),
          ListTile(
            leading: Icon(Icons.apps_rounded, color: scheme.primary),
            title: const Text('Apps & cache'),
            subtitle: const Text('App sizes, unused apps, clear cache'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(fadeSlideRoute(const AppsScreen())),
          ),
          _section(context, 'Media'),
          SwitchListTile(
            secondary: Icon(Icons.headphones_rounded, color: scheme.primary),
            title: const Text('Keep playing in the background'),
            subtitle: const Text('Audio and video sound continue when you leave the app or lock the screen'),
            value: ref.watch(backgroundPlayProvider),
            onChanged: (v) => ref.read(backgroundPlayProvider.notifier).set(v),
          ),
          _section(context, 'Files'),
          ListTile(
            leading: Icon(Icons.folder_shared_rounded, color: scheme.primary),
            title: const Text('All files access'),
            subtitle: const Text('Optional. Browse every folder, create files, write code.'),
            onTap: () async {
              final ok = await requestAllFilesAccess();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ok ? 'Access allowed' : 'Access not allowed. You can allow it in Android settings.')),
                );
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.history_toggle_off_rounded, color: scheme.primary),
            title: const Text('Clear recent files'),
            subtitle: const Text('Does not delete any file'),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Clear recent files?'),
                  content: const Text('Your files stay on your device.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
                  ],
                ),
              );
              if (ok == true) await ref.read(recentsProvider.notifier).clear();
            },
          ),
          _section(context, 'Testing'),
          ListTile(
            leading: Icon(Icons.science_rounded, color: scheme.primary),
            title: const Text('Create sample files'),
            subtitle: const Text('PDF, EPUB, Word, Excel, PowerPoint, code, ZIP, image, audio... to test every viewer'),
            onTap: () => _samples(context, ref),
          ),
          _section(context, 'Coming soon'),
          ListTile(
            leading: const Icon(Icons.cloud_upload_rounded),
            title: const Text('Backup to your Google Drive'),
            subtitle: const Text('Your own Drive. Fyleon has no cloud of its own.'),
            onTap: () => soon('Google Drive backup'),
          ),
          ListTile(
            leading: const Icon(Icons.key_rounded),
            title: const Text('AI Vault'),
            subtitle: const Text('Your own AI keys, locked with fingerprint / screen lock'),
            onTap: () => soon('AI Vault'),
          ),
          ListTile(
            leading: const Icon(Icons.workspace_premium_rounded),
            title: const Text('Fyleon Pro'),
            subtitle: const Text('No ads, all themes, advanced tools'),
            onTap: () => soon('Fyleon Pro'),
          ),
          _section(context, 'About'),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('About Fyleon'),
            subtitle: const Text('Version ${AppConstants.version}'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: AppConstants.appName,
              applicationVersion: AppConstants.version,
              applicationLegalese: 'Open anything.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Open source licenses'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: AppConstants.appName,
              applicationVersion: AppConstants.version,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _samples(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Creating sample files...')));
    try {
      final roots = storageRoots();
      String root;
      if (roots.isNotEmpty && await hasAllFilesAccess()) {
        root = p.join(roots.first.path, 'Documents');
      } else {
        root = (await getApplicationDocumentsDirectory()).path;
      }
      final path = await generateSampleFiles(root);
      messenger.hideCurrentSnackBar();
      ref.read(browsePathProvider.notifier).open(path);
      ref.read(homeTabProvider.notifier).set(0);
      messenger.showSnackBar(SnackBar(content: Text('Sample files created in $path')));
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('Could not create the samples: ${friendlyError(e).message}')));
    }
  }

  Widget _section(BuildContext context, String title) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: scheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
