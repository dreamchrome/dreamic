import 'package:dreamic/data/repos/remote_config_repo_int.dart';

class RemoteConfigRepoMockImpl implements RemoteConfigRepoInt {
  RemoteConfigRepoMockImpl(this.defaultValues);

  final Map<String, dynamic> defaultValues;

  @override
  String getString(String key) {
    return defaultValues[key] as String;
  }

  @override
  bool getBool(String key) {
    return defaultValues[key] as bool;
  }

  @override
  int getInt(String key) {
    return defaultValues[key] as int;
  }

  @override
  double getDouble(String key) {
    return defaultValues[key] as double;
  }
}
