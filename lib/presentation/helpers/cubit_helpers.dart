import 'package:dreamic/utils/logger.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// // void emitCubitSafe<T>(Cubit<T> cubit, T state) {
// //   if (!cubit.isClosed) {
// //     cubit.emitSafe(state);
// //   }
// // }

// // extension CubitExtensions<T> on Cubit<T> {
// //   void safeemitSafe(T state) {
// //     if (!isClosed) {
// //       emitSafe(state);
// //     } else {
// //       logd('Cubit is closed, cannot emit state: $state');
// //     }
// //   }
// // }

mixin SafeEmitMixin<T> on Cubit<T> {
  void emitSafe(T state) {
    // logd('SafeEmitMixin emitting state: $state');
    if (!isClosed) {
      emit(state);
    } else {
      logw(
          'Cubit was closed, could not emit state but avoided exception with SafeEmitMixin: $state');
    }
  }
}
