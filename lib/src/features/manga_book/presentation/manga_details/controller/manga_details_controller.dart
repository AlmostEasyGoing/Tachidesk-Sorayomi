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
import '../../../../library/domain/category/category_model.dart';
import '../../../data/manga_book/manga_book_repository.dart';
import '../../../domain/chapter/chapter_model.dart';
import '../../../domain/manga/manga_model.dart';

part 'manga_details_controller.g.dart';

class MangaWithId extends AsyncNotifier<MangaDto?> {
  MangaWithId(this.mangaId);
  final int mangaId;

  @override
  Future<MangaDto?> build() =>
      ref.watch(mangaBookRepositoryProvider).getManga(mangaId: mangaId);

  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

// GRAPHQL_CODEGEN_BUG
final mangaWithIdProvider = AsyncNotifierProvider.autoDispose.family<MangaWithId, MangaDto?, int>(MangaWithId.new);

class MangaChapterList extends AsyncNotifier<List<ChapterDto>?> {
  MangaChapterList(this.mangaId);
  final int mangaId;

  @override
  Future<List<ChapterDto>?> build() async {
    final result =
        await ref.watch(mangaBookRepositoryProvider).getChapterList(mangaId);
    ref.keepAlive();
    return result;
  }

  Future<void> refresh([bool onlineFetch = false]) async {
    final result = await AsyncValue.guard(
        () => ref.read(mangaBookRepositoryProvider).getChapterList(mangaId));
    ref.keepAlive();
    if (result.hasError) {
      state = result.copyWithPrevious(state);
    } else {
      state = result;
    }
  }

  void updateChapter(int index, ChapterDto chapter) {
    try {
      final newList = [...?state.asData?.value];
      newList[index] = chapter;
      state = AsyncData<List<ChapterDto>?>(newList).copyWithPrevious(state);
    } catch (e) {
      //
    }
  }
}

// GRAPHQL_CODEGEN_BUG
final mangaChapterListProvider = AsyncNotifierProvider.autoDispose.family<MangaChapterList, List<ChapterDto>?, int>(MangaChapterList.new);

@riverpod
Set<String> mangaScanlatorList(Ref ref, {required int mangaId}) {
  final chapterList = ref.watch(mangaChapterListProvider(mangaId));
  final scanlatorList = <String>{};
  chapterList.whenData((data) {
    if (data == null) return;
    for (final chapter in data) {
      if (chapter.scanlator.isNotBlank) {
        scanlatorList.add(chapter.scanlator!);
      }
    }
  });
  return scanlatorList;
}

class MangaChapterFilterScanlator extends Notifier<String> {
  MangaChapterFilterScanlator(this.mangaId);
  final int mangaId;

  @override
  String build() {
    final manga = ref.watch(mangaWithIdProvider(mangaId));
    return manga.asData?.value?.metaData.scanlator ?? MangaMetaKeys.scanlator.key;
  }

  void updateScanlator(String? scanlator) async {
    await AsyncValue.guard(
      () => ref.read(mangaBookRepositoryProvider).patchMangaMeta(
            mangaId: mangaId,
            key: MangaMetaKeys.scanlator.key,
            value: scanlator ?? MangaMetaKeys.scanlator.key,
          ),
    );
    ref.invalidate(mangaWithIdProvider(mangaId));
    state = scanlator ?? MangaMetaKeys.scanlator.key;
  }
}

final mangaChapterFilterScanlatorProvider =
    NotifierProvider.autoDispose.family<MangaChapterFilterScanlator, String, int>(
  (mangaId) => MangaChapterFilterScanlator(mangaId),
);

AsyncValue<List<ChapterDto>?> mangaChapterListWithFilter(Ref ref, {required int mangaId}) {
  final chapterList = ref.watch(mangaChapterListProvider(mangaId));
  final chapterFilterUnread = ref.watch(mangaChapterFilterUnreadProvider);
  final chapterFilterDownloaded =
      ref.watch(mangaChapterFilterDownloadedProvider);
  final chapterFilterBookmark = ref.watch(mangaChapterFilterBookmarkedProvider);
  final ChapterSort sortedBy = ref.watch(mangaChapterSortProvider) ??
      DBKeys.chapterSortDirection.initial;
  final sortedDirection =
      ref.watch(mangaChapterSortDirectionProvider).ifNull(true);

  final chapterFilterScanlator =
      ref.watch(mangaChapterFilterScanlatorProvider(mangaId));

  bool applyChapterFilter(ChapterDto chapter) {
    if (chapterFilterUnread != null &&
        (chapterFilterUnread ^ !(chapter.isRead.ifNull()))) {
      return false;
    }

    if (chapterFilterDownloaded != null &&
        (chapterFilterDownloaded ^ (chapter.isDownloaded.ifNull()))) {
      return false;
    }

    if (chapterFilterBookmark != null &&
        (chapterFilterBookmark ^ (chapter.isBookmarked.ifNull()))) {
      return false;
    }

    if (chapterFilterScanlator != MangaMetaKeys.scanlator.key &&
        chapter.scanlator != chapterFilterScanlator) {
      return false;
    }
    return true;
  }

  int applyChapterSort(ChapterDto m1, ChapterDto m2) {
    final sortDirToggle = (sortedDirection ? 1 : -1);
    return (switch (sortedBy) {
          ChapterSort.fetchedDate => (int.tryParse(m1.fetchedAt) ?? 0)
              .compareTo(int.tryParse(m2.fetchedAt) ?? 0),
          ChapterSort.source => (m1.index).compareTo(m2.index),
          ChapterSort.uploadDate => (int.tryParse(m1.uploadDate) ?? 0)
              .compareTo(int.tryParse(m2.uploadDate) ?? 0),
        }) *
        sortDirToggle;
  }

  return chapterList.copyWithData(
    (data) => [...?data?.where(applyChapterFilter)]..sort(applyChapterSort),
  );
}

// GRAPHQL_CODEGEN_BUG
final mangaChapterListWithFilterProvider =
    Provider.autoDispose.family<AsyncValue<List<ChapterDto>?>, int>(
  (ref, mangaId) => mangaChapterListWithFilter(ref, mangaId: mangaId)
);

ChapterDto? firstUnreadInFilteredChapterList(Ref ref, {required int mangaId}) {
  final isAscSorted = ref.watch(mangaChapterSortDirectionProvider) ??
      DBKeys.chapterSortDirection.initial;
  final filteredList = ref
      .watch(mangaChapterListWithFilterProvider(mangaId))
      .asData?.value;
  if (filteredList == null) {
    return null;
  } else {
    if (isAscSorted) {
      return filteredList
          .firstWhereOrNull((element) => !element.isRead.ifNull(true));
    } else {
      return filteredList
          .lastWhereOrNull((element) => !element.isRead.ifNull(true));
    }
  }
}

// GRAPHQL_CODEGEN_BUG
final firstUnreadInFilteredChapterListProvider =
    Provider.autoDispose.family<ChapterDto?, int>(
  (ref, mangaId) => firstUnreadInFilteredChapterList(ref, mangaId: mangaId),
);

({ChapterDto? first, ChapterDto? second})? getNextAndPreviousChapters(
  Ref ref, {
  required int mangaId,
  required int chapterId,
  bool? shouldAscSort,
}) {
  bool shouldAscSortWithDefault = shouldAscSort ?? true;
  final isAscSorted = ref.watch(mangaChapterSortDirectionProvider) ??
      DBKeys.chapterSortDirection.initial;
  final filteredList = ref
      .watch(mangaChapterListWithFilterProvider(mangaId))
      .asData?.value;
  if (filteredList == null) {
    return null;
  } else {
    final current =
        filteredList.indexWhere((element) => element.id == chapterId);
    final prevChapter = current > 0 ? filteredList[current - 1] : null;
    final nextChapter =
        current < (filteredList.length - 1) ? filteredList[current + 1] : null;
    return (
      first: shouldAscSortWithDefault && isAscSorted ? nextChapter : prevChapter,
      second: shouldAscSortWithDefault && isAscSorted ? prevChapter : nextChapter,
    );
  }
}

// GRAPHQL_CODEGEN_BUG
final getNextAndPreviousChaptersProvider = Provider.autoDispose.family<
  ({ChapterDto? first, ChapterDto? second})?,
  ({int mangaId, int chapterId, bool? shouldAscSort})>(
  (ref, arg) => getNextAndPreviousChapters(
    ref,
    mangaId: arg.mangaId,
    chapterId: arg.chapterId,
    shouldAscSort: arg.shouldAscSort
  )
);

@riverpod
class MangaChapterSort extends Notifier<ChapterSort?>
    with SharedPreferenceEnumClientMixin<ChapterSort> {
  @override
  ChapterSort? build() => initialize(
    DBKeys.chapterSort,
    enumList: ChapterSort.values,
  );
}

@riverpod
class MangaChapterSortDirection extends Notifier<bool?>
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.chapterSortDirection);
}

@riverpod
class MangaChapterFilterDownloaded extends Notifier<bool?>
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.chapterFilterDownloaded);
}

@riverpod
class MangaChapterFilterUnread extends Notifier<bool?>
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.chapterFilterUnread);
}

@riverpod
class MangaChapterFilterBookmarked extends Notifier<bool?>
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.chapterFilterBookmarked);
}

class MangaCategoryList extends AsyncNotifier<Map<String, CategoryDto>?> {
  MangaCategoryList(this.mangaId);
  final int mangaId;

  @override
  FutureOr<Map<String, CategoryDto>?> build() async {
    final result = await ref
        .watch(mangaBookRepositoryProvider)
        .getMangaCategoryList(mangaId: mangaId);
    return {
      for (CategoryDto i in (result ?? <CategoryDto>[])) "${i.id}": i,
    };
  }

  Future<void> refresh() async {
    final result = await AsyncValue.guard(() => ref
        .read(mangaBookRepositoryProvider)
        .getMangaCategoryList(mangaId: mangaId));
    state = result.copyWithData((data) => {
          for (CategoryDto i in (data ?? <CategoryDto>[])) "${i.id}": i,
        });
  }
}

// GRAPHQL_CODEGEN_BUG
final mangaCategoryListProvider = AsyncNotifierProvider.autoDispose.family<MangaCategoryList, Map<String, CategoryDto>?, int>(MangaCategoryList.new);
