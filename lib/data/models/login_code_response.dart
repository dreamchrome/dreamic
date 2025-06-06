import 'package:json_annotation/json_annotation.dart';

part 'login_code_response.g.dart';

@JsonSerializable()
class LoginCodeResponse {
  String email;
  String password;

  LoginCodeResponse(
    this.email,
    this.password,
  );

  factory LoginCodeResponse.fromJson(Map<String, dynamic> json) =>
      _$LoginCodeResponseFromJson(json);
  Map<String, dynamic> toJson() => _$LoginCodeResponseToJson(this);
}
