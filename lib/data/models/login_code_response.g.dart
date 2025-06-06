// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'login_code_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LoginCodeResponse _$LoginCodeResponseFromJson(Map<String, dynamic> json) =>
    LoginCodeResponse(
      json['email'] as String,
      json['password'] as String,
    );

Map<String, dynamic> _$LoginCodeResponseToJson(LoginCodeResponse instance) =>
    <String, dynamic>{
      'email': instance.email,
      'password': instance.password,
    };
