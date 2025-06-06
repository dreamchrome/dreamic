import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dreamic/presentation/helpers/app_reloader/appreloader.dart';

//TODO: change all views to only show this when an error occurs
class ErrorMessageWidget extends StatelessWidget {
  final String? errorMessage;
  final Function()? onExitTapped;

  const ErrorMessageWidget({
    super.key,
    this.errorMessage,
    this.onExitTapped,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          Center(
            child: Text(
              errorMessage ?? 'An error occurred',
              textAlign: TextAlign.center,
              // style: AppStyles.textStyleHeader,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                // color: AppColors.error,
              ),
            ),
          ),
          const SizedBox(height: 24),
          // if (errorMessage != null) Text(errorMessage!, maxLines: 4),
          // if (errorMessage != null) const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => (onExitTapped != null)
                ? onExitTapped!.call()
                : kIsWeb
                    ? reloadApp()
                    : Navigator.of(context).pop(),
            child: const Text(kIsWeb ? 'Reload' : 'Go back'),
          ),
        ],
      ),
    );
  }
}
