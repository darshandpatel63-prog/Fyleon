import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../shared/widgets/animations.dart';
import '../files/application/browse_controller.dart';
import '../files/application/files_providers.dart';
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
        padding: const EdgeInsets.only(bottom: 40),
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
