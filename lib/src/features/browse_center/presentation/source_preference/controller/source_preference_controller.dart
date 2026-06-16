// Copyright (c) 2023 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../data/source_repository/source_repository.dart';
import '../../../domain/source_preference/source_preference.dart';

Future<List<SourcePreference>?> baseSourcePreferenceList(
        Ref ref, String sourceId) =>
    ref.read(sourceRepositoryProvider).getSourcePreference(sourceId);

// GRAPHQL_CODEGEN_BUG
final baseSourcePreferenceListProvider = FutureProvider.autoDispose.family<List<SourcePreference>?, String>(baseSourcePreferenceList);
