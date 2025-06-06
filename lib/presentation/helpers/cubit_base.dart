import 'package:dreamic/presentation/helpers/cubit_helpers.dart';
import 'package:dreamic/presentation/helpers/page_statuses.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:equatable/equatable.dart';
part 'cubit_base_state.dart';

abstract class CubitBase<T extends CubitBaseState> extends Cubit<T> with SafeEmitMixin<T> {
  CubitBase(super.initialState);

  // void emitSafe(T state) {
  //   if (!isClosed) {
  //     emitSafe(state);
  //   } else {
  //     Logr.le(
  //       'Cubit was closed, could not emit state but avoided exception with SafeEmitMixin: $state',
  //     );
  //   }
  // }

  // factory CubitBase.create() => CubitBase();
  // CubitBase create();

  // getInitialData();
}
