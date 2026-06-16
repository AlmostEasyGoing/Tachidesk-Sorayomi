import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../domain/settings/settings.dart';
import '../data/backup_settings_repository.dart';

Future<RestoreStatusDto?> restoreStatus(Ref ref, String restoreId) =>
    ref.watch(backupSettingsRepositoryProvider).getRestoreStatus(restoreId);

// GRAPHQL_CODEGEN_BUG
final restoreStatusProvider = FutureProvider.autoDispose.family<RestoreStatusDto?, String>(restoreStatus);
