// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/custom_circular_progress_indicator.dart';
import '../../../../widgets/emoticons.dart';
import '../../data/updates/updates_repository.dart';
import '../../domain/chapter/chapter_model.dart';
import '../../domain/chapter/graphql/__generated__/fragment.graphql.dart';
import '../../widgets/chapter_actions/multi_chapters_actions_bottom_app_bar.dart';
import '../../widgets/update_status_fab.dart';
import '../../widgets/update_status_popup_menu.dart';
import '../reader/controller/reader_controller.dart';
import 'widgets/chapter_manga_list_tile.dart';

class UpdatesScreen extends HookConsumerWidget {
  const UpdatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updatesRepository = ref.watch(updatesRepositoryProvider);
    final isUpdatesChecking = ref
        .watch(updatesSocketProvider
            .select((value) => value.asData?.value?.isRunning))
        .ifNull();

    final selectedChapters = useState<Map<int, ChapterDto>>({});
    final pagingState = useState<PagingState<int, ChapterWithMangaDto>>(PagingState());

    Future<void> fetchNextPage() async {
      final state = pagingState.value;
      if (state.isLoading || !state.hasNextPage) return;

      pagingState.value = state.copyWith(isLoading: true);

      final pageKey = (state.keys?.last ?? -1) + 1;

      final result = await AsyncValue.guard(
        () => updatesRepository.getRecentChaptersPage(pageNo: pageKey),
      );

      result.whenOrNull(
        data: (recentChaptersPage) {
          if (recentChaptersPage == null) return;
          pagingState.value = pagingState.value.copyWith(
            pages: [...?pagingState.value.pages, recentChaptersPage.nodes],
            keys: [...?pagingState.value.keys, pageKey],
            hasNextPage: recentChaptersPage.pageInfo.hasNextPage,
            isLoading: false,
            error: null,
          );
        },
        error: (error, _) {
          pagingState.value = pagingState.value.copyWith(
            error: error,
            isLoading: false,
          );
        },
      );
    }

    void refresh() {
      pagingState.value = PagingState();
      fetchNextPage();
    }

    // Initial load
    useEffect(() {
      fetchNextPage();
      return null;
    }, []);

    // Refresh when update check finishes
    useEffect(() {
      if (!isUpdatesChecking) {
        selectedChapters.value = {};
        refresh();
      }
      return null;
    }, [isUpdatesChecking]);

    final state = pagingState.value;
    final items = state.items ?? [];

    return Scaffold(
      floatingActionButton:
          selectedChapters.value.isEmpty ? const UpdateStatusFab() : null,
      appBar: selectedChapters.value.isNotEmpty
          ? AppBar(
              leading: IconButton(
                onPressed: () => selectedChapters.value = {},
                icon: const Icon(Icons.close_rounded),
              ),
              title: Text(
                context.l10n.numSelected(selectedChapters.value.length),
              ),
            )
          : AppBar(
              title: Text(context.l10n.updates),
              actions: const [UpdateStatusPopupMenu()],
            ),
      bottomSheet: selectedChapters.value.isNotEmpty
          ? MultiChaptersActionsBottomAppBar(
              selectedChapters: selectedChapters,
              afterOptionSelected: () async => refresh(),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          selectedChapters.value = {};
          refresh();
        },
        child: PagedListView<int, ChapterWithMangaDto>(
          state: state,
          fetchNextPage: fetchNextPage,
          builderDelegate: PagedChildBuilderDelegate<ChapterWithMangaDto>(
            firstPageProgressIndicatorBuilder: (context) =>
                const CenterSorayomiShimmerIndicator(),
            firstPageErrorIndicatorBuilder: (context) => Emoticons(
              title: state.error.toString(),
              button: TextButton(
                onPressed: refresh,
                child: Text(context.l10n.retry),
              ),
            ),
            noItemsFoundIndicatorBuilder: (context) => Emoticons(
              title: context.l10n.noUpdatesFound,
              button: TextButton(
                onPressed: refresh,
                child: Text(context.l10n.refresh),
              ),
            ),
            itemBuilder: (context, item, index) {
              int? previousDate;
              try {
                previousDate =
                    int.tryParse(items[index - 1].fetchedAt);
              } catch (e) {
                previousDate = null;
              }
              final chapterTile = ChapterMangaListTile(
                chapterWithMangaDto: item,
                updatePair: () async {
                  final chapter =
                      await ref.refresh(chapterProvider(item.id).future);
                  try {
                    pagingState.value = pagingState.value.mapItems(
                      (i) => i.id == item.id
                          ? i.copyWith(
                              isDownloaded: chapter?.isDownloaded,
                              lastPageRead: chapter?.lastPageRead,
                            )
                          : i,
                    );
                  } catch (e) {
                    //
                  }
                },
                isSelected: selectedChapters.value.containsKey(item.id),
                canTapSelect: selectedChapters.value.isNotEmpty,
                toggleSelect: (ChapterDto val) {
                  if ((val.id).isNull) return;
                  selectedChapters.value =
                      selectedChapters.value.toggleKey(val.id, val);
                },
              );
              if ((int.tryParse(item.fetchedAt)).isSameDayAs(previousDate)) {
                return chapterTile;
              } else {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: Text(
                        int.tryParse(item.fetchedAt)
                            .toDaysAgoFromSeconds(context),
                      ),
                    ),
                    chapterTile,
                  ],
                );
              }
            },
          ),
        ),
      ),
    );
  }
}
