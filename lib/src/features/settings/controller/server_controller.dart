import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../data/settings_repository.dart';
import '../domain/settings/settings.dart';

class Settings extends AsyncNotifier<SettingsDto?> {
  @override
  Future<SettingsDto?> build() =>
      ref.watch(settingsRepositoryProvider).getServerSettings();

  void updateState(SettingsDto value) =>
      state = state.copyWithData((_) => value);
}

// GRAPHQL_CODEGEN_BUG
final settingsProvider = AsyncNotifierProvider.autoDispose<Settings, SettingsDto?>(Settings.new);
