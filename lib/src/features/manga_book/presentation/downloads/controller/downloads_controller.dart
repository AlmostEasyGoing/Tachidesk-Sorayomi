import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../data/downloads/downloads_repository.dart';
import '../../../domain/downloads/downloads_model.dart';
import '../../../domain/downloads_queue/downloads_queue_model.dart';

part 'downloads_controller.g.dart';

Stream<DownloadUpdatesDto?> downloadUpdates(Ref ref) =>
    ref.watch(downloadsRepositoryProvider).downloadStatusSubscription();

// GRAPHQL_CODEGEN_BUG
final downloadUpdatesProvider = StreamProvider.autoDispose<DownloadUpdatesDto?>(downloadUpdates);

Future<DownloadStatusDto?> downloadStatus(Ref ref) =>
    ref.watch(downloadsRepositoryProvider).getDownloadStatus();

// GRAPHQL_CODEGEN_BUG
final downloadStatusProvider = FutureProvider.autoDispose<DownloadStatusDto?>(downloadStatus);

class DownloadsMap extends Notifier<Map<int, DownloadDto>> {
  void updateDownloadStatus(DownloadUpdatesDto? downloadStatusDto) {
    final currState = {...?stateOrNull};
    for (final element in [...?downloadStatusDto?.initial]) {
      currState[element.chapter.id] = element;
    }
    for (final element in [...?downloadStatusDto?.updates]) {
      switch (element.type) {
        case DownloadUpdateType.DEQUEUED:
        case DownloadUpdateType.FINISHED:
          currState.remove(element.download.chapter.id);
          break;
        case DownloadUpdateType.QUEUED:
        case DownloadUpdateType.PROGRESS:
        case DownloadUpdateType.POSITION:
        case DownloadUpdateType.PAUSED:
        case DownloadUpdateType.ERROR:
        case DownloadUpdateType.STOPPED:
          currState[element.download.chapter.id] = element.download;
          break;
        case DownloadUpdateType.$unknown:
          throw UnimplementedError();
      }
    }
    if (stateOrNull != null) {
      state = currState;
    }
  }

  @override
  Map<int, DownloadDto> build() {
    ref.listen(downloadUpdatesProvider,
        (_, next) => updateDownloadStatus(next.asData?.value));
    final downloadStatusDto = ref.watch(downloadStatusProvider).asData?.value;
    return getStateFromUpdates(downloadStatusDto);
  }

  Map<int, DownloadDto> getStateFromUpdates(
      DownloadStatusDto? downloadStatusDto) {
    final downloadsMap = <int, DownloadDto>{};
    for (final element in [...?downloadStatusDto?.queue]) {
      downloadsMap[element.chapter.id] = element;
    }
    return downloadsMap;
  }

  void reorder(int chapterId, int to) async {
    final downloadStatusDto = await ref
        .read(downloadsRepositoryProvider)
        .reorderDownload(chapterId, to);
    state = getStateFromUpdates(downloadStatusDto);
  }
}

// GRAPHQL_CODEGEN_BUG
final downloadsMapProvider = NotifierProvider.autoDispose<DownloadsMap, Map<int, DownloadDto>>(DownloadsMap.new);

DownloadDto? downloadsFromId(Ref ref, int chapterId) =>
    ref.watch(downloadsMapProvider.select((map) => map[chapterId]));

// GRAPHQL_CODEGEN_BUG
final downloadsFromIdProvider = Provider.autoDispose.family<DownloadDto?, int>(downloadsFromId);

@riverpod
List<int> downloadsChapterIds(Ref ref) {
  final downloads = ref.watch(downloadsMapProvider).values.toList();
  downloads.sort((a, b) => a.position.compareTo(b.position));
  return downloads.map((d) => d.chapter.id).toList();
}

AsyncValue<DownloaderState?> downloaderState(Ref ref) {
  return ref.watch(downloadUpdatesProvider
      .select((value) => value.copyWithData((data) => data?.state)));
}

// GRAPHQL_CODEGEN_BUG
final downloaderStateProvider = Provider.autoDispose<AsyncValue<DownloaderState?>>(downloaderState);

@riverpod
bool showDownloadsFAB(Ref ref) {
  final downloads = ref.watch(downloadUpdatesProvider);
  final value = downloads.asData?.value;
  return value?.state == DownloaderState.STARTED ||
      (value?.updates)?.isNotBlank == true &&
          value!.updates.any(
            (element) =>
                element.download.state != DownloadState.ERROR ||
                element.download.tries != 3,
          );
}
