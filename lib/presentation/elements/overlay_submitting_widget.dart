import 'package:flutter/material.dart';

import 'frosted_container_widget.dart';
import 'loading_indicator.dart';

class OverlaySubmitting extends StatelessWidget {
  const OverlaySubmitting({super.key});

  @override
  Widget build(BuildContext context) {
    return FrostedContainerWidget(
      opacity: 20,
      child: SizedBox(
        height: MediaQuery.of(context).size.height,
        width: MediaQuery.of(context).size.width,
        child: const Center(
          child: LoadingIndicator(radius: 30),
        ),
      ),
    );
  }
}
