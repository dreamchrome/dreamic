import 'package:json_annotation/json_annotation.dart';

part 'login_code_request.g.dart';

@JsonSerializable()
class LoginCodeRequest {
  String action = 'authLoginWithCode';
  String loginCode;

  LoginCodeRequest({
    required this.loginCode,
  });

  factory LoginCodeRequest.fromJson(Map<String, dynamic> json) =>
      _$LoginCodeRequestFromJson(json);
  Map<String, dynamic> toJson() => _$LoginCodeRequestToJson(this);
}
