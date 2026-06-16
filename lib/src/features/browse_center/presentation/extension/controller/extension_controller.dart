// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../../utils/mixin/state_provider_mixin.dart';
import '../../../../settings/presentation/browse/widgets/show_nsfw_switch/show_nsfw_switch.dart';
import '../../../data/extension_repository/extension_repository.dart';
import '../../../domain/extension/extension_model.dart';

part 'extension_controller.g.dart';

Future<List<Extension>?> extension(Ref ref) {
  final result =
      ref.watch(extensionRepositoryProvider).getExtensionListStream();
  return result;
}

// GRAPHQL_CODEGEN_BUG
final extensionProvider = FutureProvider<List<Extension>?>((ref) => extension(ref));

AsyncValue<Map<String, List<Extension>>> extensionMap(Ref ref) {
  final extensionMap = <String, List<Extension>>{};
  final extensionListData = ref.watch(extensionProvider);
  final extensionList = [...?extensionListData.asData?.value];
  final showNsfw = ref.watch(showNSFWProvider).ifNull(true);
  for (final e in extensionList) {
    if (!showNsfw && (e.isNsfw.ifNull())) continue;
    if (e.isInstalled.ifNull()) {
      if (e.hasUpdate.ifNull()) {
        extensionMap.update(
          "update",
          (value) => [...value, e],
          ifAbsent: () => [e],
        );
      } else {
        extensionMap.update(
          "installed",
          (value) => [...value, e],
          ifAbsent: () => [e],
        );
      }
    } else {
      extensionMap.update(
        e.language?.code?.toLowerCase() ?? "other",
        (value) => [...value, e],
        ifAbsent: () => [e],
      );
    }
  }
  return extensionListData.copyWithData((p0) => extensionMap);
}

// GRAPHQL_CODEGEN_BUG
final extensionMapProvider = Provider.autoDispose<AsyncValue<Map<String, List<Extension>>>>(extensionMap);

@riverpod
List<String> extensionFilterLangList(Ref ref) {
  final extensionMap = {...?ref.watch(extensionMapProvider).asData?.value};
  extensionMap.remove("installed");
  extensionMap.remove("update");
  return [...extensionMap.keys]..sort();
}

@riverpod
class ExtensionLanguageFilter extends Notifier<List<String>?>
    with SharedPreferenceClientMixin<List<String>> {
  @override
  List<String>? build() => initialize(DBKeys.extensionLanguageFilter);
}

AsyncValue<Map<String, List<Extension>>> extensionMapFiltered(Ref ref) {
  final extensionMapFiltered = <String, List<Extension>>{};
  final extensionMapData = ref.watch(extensionMapProvider);
  final extensionMap = {...?extensionMapData.asData?.value};
  final enabledLangList = [...?ref.watch(extensionLanguageFilterProvider)];
  for (final e in enabledLangList) {
    if (extensionMap.containsKey(e)) extensionMapFiltered[e] = extensionMap[e]!;
  }
  return extensionMapData.copyWithData((p0) => extensionMapFiltered);
}

// GRAPHQL_CODEGEN_BUG
final extensionMapFilteredProvider = Provider.autoDispose<AsyncValue<Map<String, List<Extension>>>>(extensionMapFiltered);

@riverpod
class ExtensionQuery extends Notifier<String?>
  with StateProviderMixin<String?> {
  @override
  String? build() => null;
}

AsyncValue<Map<String, List<Extension>>> extensionMapFilteredAndQueried(Ref ref) {
  final extensionMapData = ref.watch(extensionMapFilteredProvider);
  final extensionMap = {...?extensionMapData.asData?.value};
  final query = ref.watch(extensionQueryProvider);
  if (query.isBlank) return extensionMapData;
  return extensionMapData.copyWithData(
    (e) => extensionMap.map<String, List<Extension>>(
      (key, value) => MapEntry(
        key,
        value.where((element) => element.name.query(query)).toList(),
      ),
    ),
  );
}

// GRAPHQL_CODEGEN_BUG
final extensionMapFilteredAndQueriedProvider = Provider.autoDispose<AsyncValue<Map<String, List<Extension>>>>(extensionMapFilteredAndQueried);
