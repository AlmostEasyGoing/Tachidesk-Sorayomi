// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '../../../../constants/app_sizes.dart';
import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/search_field.dart';
import '../../../manga_book/domain/manga/manga_model.dart';
import '../../data/source_repository/source_repository.dart';
import '../../domain/filter/filter_model.dart';
import '../../domain/source/source_model.dart';
import 'controller/source_manga_controller.dart';
import 'widgets/source_manga_display_icon_popup.dart';
import 'widgets/source_manga_display_view.dart';
import 'widgets/source_manga_filter.dart';
import 'widgets/source_type_selectable_chip.dart';

class SourceMangaListScreen extends HookConsumerWidget {
  const SourceMangaListScreen({
    super.key,
    required this.sourceId,
    required this.sourceType,
    this.initialQuery,
  });
  final String sourceId;
  final SourceType sourceType;
  final String? initialQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourceRepository = ref.watch(sourceRepositoryProvider);
    final appliedFilter = useState<List<FilterChange>>([]);
    final filterList =
        ref.watch(baseSourceMangaFilterListProvider(sourceId)).asData?.value;
    final source = ref.watch(sourceProvider(sourceId));

    final query = useState(initialQuery);
    final showSearch = useState(initialQuery.isNotBlank);

    final pagingState = useState<PagingState<int, MangaDto>>(PagingState());

    Future<void> fetchNextPage() async {
      final state = pagingState.value;
      if (state.isLoading || !state.hasNextPage) return;

      pagingState.value = state.copyWith(isLoading: true);

      final pageKey = (state.keys?.last ?? 0) + 1; // API is 1-indexed

      final result = await AsyncValue.guard(
        () => sourceRepository.fetchSourceManga(
          sourceId: sourceId,
          sourceType: sourceType,
          page: pageKey,
          query: query.value,
          filters: appliedFilter.value,
        ),
      );

      result.whenOrNull(
        data: (recentMangaPage) {
          if (recentMangaPage == null) return;
          pagingState.value = pagingState.value.copyWith(
            pages: [...?pagingState.value.pages, recentMangaPage.mangas],
            keys: [...?pagingState.value.keys, pageKey],
            hasNextPage: recentMangaPage.hasNextPage.ifNull(),
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

    return source.showUiWhenData(
      context,
      (data) => Scaffold(
        appBar: AppBar(
          title: Text(data?.displayName ?? context.l10n.source),
          actions: [
            IconButton(
              onPressed: () => showSearch.value = true,
              icon: const Icon(Icons.search_rounded),
            ),
            const SourceMangaDisplayIconPopup(),
            if ((data?.isConfigurable).ifNull())
              IconButton(
                onPressed: () => SourcePreferenceRoute(
                  sourceId: sourceId,
                ).go(context),
                icon: const Icon(Icons.settings_rounded),
              ),
          ],
          bottom: PreferredSize(
            preferredSize: kCalculateAppBarBottomSize([true, showSearch.value]),
            child: Column(
              children: [
                Row(
                  children: [
                    SourceTypeSelectableChip(
                      value: SourceType.POPULAR,
                      groupValue: sourceType,
                      onSelected: (_) {
                        if (sourceType == SourceType.POPULAR) return;
                        SourceTypeRoute(
                          sourceId: sourceId,
                          sourceType: SourceType.POPULAR,
                        ).go(context);
                      },
                    ),
                    if ((data?.supportsLatest).ifNull())
                      SourceTypeSelectableChip(
                        value: SourceType.LATEST,
                        groupValue: sourceType,
                        onSelected: (_) {
                          if (sourceType == SourceType.LATEST) return;
                          SourceTypeRoute(
                            sourceId: sourceId,
                            sourceType: SourceType.LATEST,
                          ).go(context);
                        },
                      ),
                    Builder(
                      builder: (context) => SourceTypeSelectableChip(
                        value: SourceType.SEARCH,
                        groupValue: sourceType,
                        onSelected: (_) => SourceTypeRoute(
                          sourceId: sourceId,
                          sourceType: SourceType.SEARCH,
                        ).go(context),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 0),
                if (showSearch.value)
                  Align(
                    alignment: Alignment.centerRight,
                    child: SearchField(
                      initialText: query.value,
                      onClose: () => showSearch.value = false,
                      onSubmitted: (val) {
                        if (sourceType == SourceType.SEARCH) {
                          query.value = val;
                          refresh();
                        } else {
                          if (val == null) return;
                          SourceTypeRoute(
                            sourceId: sourceId,
                            sourceType: SourceType.SEARCH,
                            query: val,
                          ).go(context);
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        endDrawer: filterList.isNotBlank
            ? Drawer(
                width: kDrawerWidth,
                shape: const RoundedRectangleBorder(),
                child: Builder(
                  builder: (context) => SourceMangaFilter(
                    filters: filterList?.toList() ?? [],
                    sourceId: sourceId,
                    onReset: () => appliedFilter.value = [],
                    onSubmitted: (value) {
                      Navigator.pop(context);
                      appliedFilter.value = value ?? [];
                      refresh();
                    },
                  ),
                ),
              )
            : null,
        body: RefreshIndicator(
          onRefresh: () async => refresh(),
          child: SourceMangaDisplayView(
            sourceId: sourceId,
            sourceType: sourceType,
            state: pagingState.value,       // ← changed
            fetchNextPage: fetchNextPage,   // ← changed
            source: data,
          ),
        ),
        floatingActionButton:
            sourceType == SourceType.SEARCH && filterList.isNotBlank
                ? Builder(
                    builder: (context) => FloatingActionButton.extended(
                      icon: const Icon(Icons.filter_alt_rounded),
                      onPressed: () => context.isTablet
                          ? Scaffold.of(context).openEndDrawer()
                          : showModalBottomSheet(
                              context: context,
                              builder: (context) => SourceMangaFilter(
                                filters: filterList?.toList() ?? [],
                                sourceId: sourceId,
                                onReset: () => appliedFilter.value = [],
                                onSubmitted: (value) {
                                  Navigator.pop(context);
                                  appliedFilter.value = value ?? [];
                                  refresh();
                                },
                              ),
                            ),
                      label: Text(context.l10n.filter),
                    ),
                  )
                : null,
      ),
      refresh: () => ref.refresh(sourceProvider(sourceId)),
      wrapper: (body) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.source)),
        body: body,
      ),
    );
  }
}
