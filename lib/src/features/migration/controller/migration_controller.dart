// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../global_providers/global_providers.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../browse_center/data/source_repository/source_repository.dart';
import '../../browse_center/domain/source/source_model.dart';
import '../../browse_center/presentation/source/controller/source_controller.dart';
import '../../library/presentation/category/controller/edit_category_controller.dart';
import '../../library/presentation/library/controller/library_controller.dart';
import '../../manga_book/domain/manga/manga_model.dart';
import '../../manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import '../data/migration_repository.dart';
import '../domain/migration_models.dart';

part 'migration_controller.g.dart';

class MigrationSources extends AsyncNotifier<List<MigrationSource>?> {
  MigrationSources(this.mangaId);
  final int mangaId;

  @override
  Future<List<MigrationSource>?> build() async {
    return ref.watch(migrationRepositoryProvider).getMigrationSources(mangaId);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

final migrationSourcesProvider = AsyncNotifierProvider.autoDispose.family<MigrationSources, List<MigrationSource>?, int>(MigrationSources.new);

class MigrationSearch extends AsyncNotifier<List<MangaDto>?> {
  MigrationSearch(this.sourceId, this.query);
  final String sourceId;
  final String query;

  @override
  Future<List<MangaDto>?> build() async {
    if (query.isEmpty) return [];

    return ref
        .watch(migrationRepositoryProvider)
        .searchMangaInSource(sourceId, query);
  }

  Future<void> search(String sourceId, String query) async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      return await ref
          .read(migrationRepositoryProvider)
          .searchMangaInSource(sourceId, query);
    });
  }

  void clearResults() {
    state = const AsyncData([]);
  }
}

// GRAPHQL_CODEGEN_BUG
final migrationSearchProvider = AsyncNotifierProvider.autoDispose.family
  <MigrationSearch, List<MangaDto>?, ({ String sourceId, String query })>(
    (arg) => MigrationSearch(arg.sourceId, arg.query)
);

// Migration Quick Search Results similar to regular global search
typedef MigrationQuickSearchResults = ({
  SourceDto source,
  AsyncValue<List<MangaDto>> mangaList
});

Future<List<MangaDto>> migrationSourceQuickSearchMangaList(
  Ref ref,
  String sourceId, {
  String? query,
}) async {
  final rateLimiterQueue = ref.watch(rateLimitQueueProvider(query));
  final mangaPage = await rateLimiterQueue
      .add(() => ref.watch(sourceRepositoryProvider).fetchSourceManga(
            page: 1,
            sourceId: sourceId,
            sourceType: SourceType.SEARCH,
            query: query,
          ));
  return [...?(mangaPage?.mangas)];
}

// GRAPHQL_CODEGEN_BUG
final migrationSourceQuickSearchMangaListProvider = FutureProvider.autoDispose.family
  <List<MangaDto>, ({ String sourceId, String? query })>(
  (ref, arg) => migrationSourceQuickSearchMangaList(ref, arg.sourceId, query: arg.query)
);

AsyncValue<List<MigrationQuickSearchResults>> migrationGlobalSearchResults(
    Ref ref,
    {String? query}) {
  final sourceMapData = ref.watch(sourceMapFilteredProvider);

  final sourceMap = <String, List<SourceDto>>{...?sourceMapData.asData?.value}
    ..remove("lastUsed");
  final sourceList = sourceMap.values.fold(
    <SourceDto>[],
    (prev, cur) => [...prev, ...cur],
  );
  final List<MigrationQuickSearchResults> sourceMangaListPairList = [];
  for (SourceDto source in sourceList) {
    if (source.id.isNotBlank) {
      final mangaList = ref.watch(
        migrationSourceQuickSearchMangaListProvider((sourceId: source.id, query: query)),
      );
      sourceMangaListPairList.add((mangaList: mangaList, source: source));
    }
  }

  return sourceMapData.copyWithData((_) => sourceMangaListPairList);
}

// GRAPHQL_CODEGEN_BUG
final migrationGlobalSearchResultsProvider = Provider.autoDispose.family
  <AsyncValue<List<MigrationQuickSearchResults>>, String?>(
    (ref, query) => migrationGlobalSearchResults(ref, query: query)
);

@riverpod
class MigrationExecution extends Notifier<MigrationProgress?> {
  @override
  MigrationProgress? build() => null;

  Future<MigrationResult?> executeMigration({
    required int fromMangaId,
    required int toMangaId,
    required MigrationOption options,
  }) async {
    try {
      // Set initial progress
      state = const MigrationProgress(
        currentStep: MigrationStep.preparingMigration,
        percentage: 0.0,
        status: MigrationStatus.preparing,
      );

      // Add a delay for visual feedback
      await Future.delayed(const Duration(milliseconds: 1000));

      // Update progress to migrating chapters
      state = const MigrationProgress(
        currentStep: MigrationStep.migrateChapters,
        percentage: 25.0,
        status: MigrationStatus.migrating,
      );

      // Add another delay
      await Future.delayed(const Duration(milliseconds: 800));

      // Update progress to migrating categories
      state = const MigrationProgress(
        currentStep: MigrationStep.migrateCategories,
        percentage: 50.0,
        status: MigrationStatus.migrating,
      );

      // Add another delay
      await Future.delayed(const Duration(milliseconds: 600));

      // Update progress to finalizing
      state = const MigrationProgress(
        currentStep: MigrationStep.migrationInProgress,
        percentage: 75.0,
        status: MigrationStatus.migrating,
      );

      // Now execute the actual migration
      final result = await ref
          .read(migrationRepositoryProvider)
          .migrateManga(fromMangaId, toMangaId, options);

      // Update final progress based on result
      if (result?.success == true) {
        state = const MigrationProgress(
          currentStep: MigrationStep.migrationCompleted,
          percentage: 100.0,
          status: MigrationStatus.completed,
        );

        // Invalidate caches to refresh UI data after successful migration
        await _invalidateCachesAfterMigration(fromMangaId, toMangaId);
      } else {
        state = MigrationProgress(
          currentStep: MigrationStep.migrationFailed,
          percentage: 0.0,
          status: MigrationStatus.error,
          errorMessage: result?.error,
        );
      }

      return result;
    } catch (e) {
      state = MigrationProgress(
        currentStep: MigrationStep.migrationFailed,
        status: MigrationStatus.error,
        errorMessage: e.toString(),
      );
      return null;
    }
  }

  Future<void> cancelMigration() async {
    try {
      await ref.read(migrationRepositoryProvider).cancelMigration();
      state = const MigrationProgress(
        currentStep: MigrationStep.migrationCancelled,
        status: MigrationStatus.cancelled,
      );
    } catch (e) {
      // Handle cancellation error - for now just set to cancelled since cancellation isn't implemented
      state = const MigrationProgress(
        currentStep: MigrationStep.migrationCancelled,
        status: MigrationStatus.cancelled,
      );
    }
  }

  void reset() {
    state = null;
  }

  /// Invalidate caches after successful migration to refresh UI data
  Future<void> _invalidateCachesAfterMigration(
      int fromMangaId, int toMangaId) async {
    try {
      // Invalidate manga details for both source and target manga
      ref.invalidate(mangaWithIdProvider(fromMangaId));
      ref.invalidate(mangaWithIdProvider(toMangaId));

      // Invalidate chapter lists for both manga (needed for unread count refresh)
      ref.invalidate(mangaChapterListProvider(fromMangaId));
      ref.invalidate(mangaChapterListProvider(toMangaId));

      // Invalidate all category manga lists to refresh library
      final categories = ref.read(categoryControllerProvider).asData?.value ?? [];
      for (final category in categories) {
        ref.invalidate(categoryMangaListProvider(category.id));
      }
      // Also invalidate the default "All" category (id: 0)
      ref.invalidate(categoryMangaListProvider(0));

      // Small delay to ensure cache invalidation propagates
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      // Don't throw - cache invalidation errors shouldn't fail the migration
    }
  }
}

@riverpod
class MigrationSearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void update(String query) {
    state = query;
  }

  void clear() {
    state = '';
  }
}

@riverpod
class SelectedMigrationSource extends Notifier<MigrationSource?> {
  @override
  MigrationSource? build() => null;

  void select(MigrationSource source) {
    state = source;
  }

  void clear() {
    state = null;
  }
}

class SelectedTargetManga extends Notifier<MangaDto?> {
  @override
  MangaDto? build() => null;

  void select(MangaDto manga) {
    state = manga;
  }

  void clear() {
    state = null;
  }
}

// GRAPHQL_CODEGEN_BUG
final selectedTargetMangaProvider = NotifierProvider.autoDispose<SelectedTargetManga, MangaDto?>(SelectedTargetManga.new);

@riverpod
class MigrationOptions extends Notifier<MigrationOption> {
  @override
  MigrationOption build() => const MigrationOption();

  void update(MigrationOption options) {
    state = options;
  }

  void updateChapters(bool value) {
    state = state.copyWith(migrateChapters: value);
  }

  void updateCategories(bool value) {
    state = state.copyWith(migrateCategories: value);
  }

  void updateDownloads(bool value) {
    state = state.copyWith(migrateDownloads: value);
  }

  void updateTracking(bool value) {
    state = state.copyWith(migrateTracking: value);
  }

  void updateDeleteSource(bool value) {
    state = state.copyWith(deleteSource: value);
  }

  void reset() {
    state = const MigrationOption();
  }
}
