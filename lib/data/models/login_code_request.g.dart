// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'login_code_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LoginCodeRequest _$LoginCodeRequestFromJson(Map<String, dynamic> json) =>
    LoginCodeRequest(
      loginCode: json['loginCode'] as String,
    )..action = json['action'] as String;

Map<String, dynamic> _$LoginCodeRequestToJson(LoginCodeRequest instance) =>
    <String, dynamic>{
      'action': instance.action,
      'loginCode': instance.loginCode,
    };
