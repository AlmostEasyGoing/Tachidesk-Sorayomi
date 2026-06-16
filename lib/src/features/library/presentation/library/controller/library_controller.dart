// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../constants/enum.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../../utils/mixin/state_provider_mixin.dart';
import '../../../../manga_book/domain/manga/manga_model.dart';
import '../../../data/category_repository.dart';
import '../../../domain/category/category_model.dart';

part 'library_controller.g.dart';

Future<List<MangaDto>?> categoryMangaList(Ref ref, int categoryId) => ref
    .watch(categoryRepositoryProvider)
    .getMangasFromCategory(categoryId: categoryId);

// GRAPHQL_CODEGEN_BUG
final categoryMangaListProvider = FutureProvider.autoDispose.family<List<MangaDto>?, int>(categoryMangaList);

class LibraryDisplayCategory extends Notifier<CategoryDto?>
    with StateProviderMixin<CategoryDto?> {
  @override
  CategoryDto? build() => null;
}

// GRAPHQL_CODEGEN_BUG
final libraryDisplayCategoryProvider = NotifierProvider.autoDispose<LibraryDisplayCategory, CategoryDto?>(LibraryDisplayCategory.new);

class CategoryMangaListWithQueryAndFilter extends Notifier<AsyncValue<List<MangaDto>?>> {
  CategoryMangaListWithQueryAndFilter(this.categoryId);
  final int categoryId;

  @override
  AsyncValue<List<MangaDto>?> build() {
    final mangaList = ref.watch(categoryMangaListProvider(categoryId));
    final query = ref.watch(libraryQueryProvider);
    final mangaFilterUnread = ref.watch(libraryMangaFilterUnreadProvider);
    final mangaFilterDownloaded =
        ref.watch(libraryMangaFilterDownloadedProvider);
    final mangaFilterCompleted = ref.watch(libraryMangaFilterCompletedProvider);
    final MangaSort sortedBy =
        ref.watch(libraryMangaSortProvider) ?? DBKeys.mangaSort.initial;
    final sortedDirection =
        ref.watch(libraryMangaSortDirectionProvider).ifNull(true);

    bool applyMangaFilter(MangaDto manga) {
      if (mangaFilterUnread != null &&
          (mangaFilterUnread ^ manga.unreadCount.isGreaterThan(0))) {
        return false;
      }

      if (mangaFilterDownloaded != null &&
          (mangaFilterDownloaded ^ manga.downloadCount.isGreaterThan(0))) {
        return false;
      }

      if (mangaFilterCompleted != null &&
          (mangaFilterCompleted ^ (manga.status.name == "COMPLETED"))) {
        return false;
      }

      if (!manga.query(query)) {
        return false;
      }

      return true;
    }

    int applyMangaSort(MangaDto m1, MangaDto m2) {
      final sortDirToggle = (sortedDirection ? 1 : -1);
      return (switch (sortedBy) {
            MangaSort.alphabetical => (m1.title).compareTo(m2.title),
            MangaSort.unread => (m1.unreadCount.getValueOnNullOrNegative())
                .compareTo(m2.unreadCount.getValueOnNullOrNegative()),
            MangaSort.dateAdded => (m1.inLibraryAt.getValueOnNullOrNegative())
                .compareTo(m2.inLibraryAt.getValueOnNullOrNegative()),
            MangaSort.lastUpdated =>
              (int.tryParse(m1.latestFetchedChapter?.fetchedAt ?? '0') ?? 0)
                  .compareTo(
                      int.tryParse(m2.latestFetchedChapter?.fetchedAt ?? '0') ??
                          0),
          }) *
          sortDirToggle;
    }

    return mangaList.map<AsyncValue<List<MangaDto>?>>(
      data: (e) => AsyncData(e.asData?.value?.where(applyMangaFilter).toList()
        ?..sort(applyMangaSort)),
      error: (e) => e,
      loading: (e) => e,
    );
  }

  void invalidate() => ref.invalidate(categoryMangaListProvider(categoryId));
}

// GRAPHQL_CODEGEN_BUG
final categoryMangaListWithQueryAndFilterProvider = NotifierProvider.autoDispose.family
  <CategoryMangaListWithQueryAndFilter, AsyncValue<List<MangaDto>?>, int>(CategoryMangaListWithQueryAndFilter.new);

@riverpod
class LibraryQuery extends Notifier<String?> with StateProviderMixin<String?> {
  @override
  String? build() => null;
}

@riverpod
class LibraryMangaFilterDownloaded extends Notifier<bool?>
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.mangaFilterDownloaded);
}

@riverpod
class LibraryMangaFilterUnread extends Notifier<bool?>
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.mangaFilterUnread);
}

@riverpod
class LibraryMangaFilterCompleted extends Notifier<bool?>
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.mangaFilterCompleted);
}

@riverpod
class LibraryMangaSort extends Notifier<MangaSort?>
    with SharedPreferenceEnumClientMixin<MangaSort> {
  @override
  MangaSort? build() => initialize(
        DBKeys.mangaSort,
        enumList: MangaSort.values,
      );
}

@riverpod
class LibraryMangaSortDirection extends Notifier<bool?>
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.mangaSortDirection);
}

@riverpod
class LibraryDisplayMode extends Notifier<DisplayMode?>
    with SharedPreferenceEnumClientMixin<DisplayMode> {
  @override
  DisplayMode? build() => initialize(
        DBKeys.libraryDisplayMode,
        enumList: DisplayMode.values,
      );
}
