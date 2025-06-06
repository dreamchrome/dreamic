import 'package:flutter/material.dart';
import 'package:dreamic/app/app_cubit.dart';
import 'package:dreamic/presentation/elements/frosted_container_widget.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';

class OverlayProgress extends StatelessWidget {
  const OverlayProgress({
    super.key,
    //TODO: need a way to set this in the consumer app
    this.progressColor = Colors.black,
    this.backgroundColor = Colors.white,
    this.blurAmount = 15.0,
    this.opacity = 130,
    required this.headerText,
  });

  final Color progressColor;
  final Color backgroundColor;
  final double blurAmount;
  final int opacity;
  final String headerText;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: FrostedContainerWidget(
        opacity: opacity,
        blurAmount: blurAmount,
        color: backgroundColor,
        child: Material(
          type: MaterialType.transparency,
          child: Center(
            child: Column(
              children: [
                const Expanded(
                  child: SizedBox(),
                ),
                SizedBox(
                  height: 50.0,
                  child: Text(
                    headerText,
                    style: const TextStyle(color: Colors.black, fontSize: 24.0),
                  ),
                ),
                SizedBox(
                  height: 120.0,
                  child: BlocBuilder<AppCubit, AppState>(
                    builder: (context, state) {
                      return CircularPercentIndicator(
                        lineWidth: 12.0,
                        center: Text(
                          '${((state.progress.isFinite ? state.progress : 0.0) * 100).toInt().toString()}%',
                          style: const TextStyle(color: Colors.black, fontSize: 18.0),
                        ),
                        radius: 60.0,
                        percent: (state.progress.isFinite ? state.progress : 0.0),
                        progressColor: progressColor,
                        backgroundColor: Colors.black,
                        circularStrokeCap: CircularStrokeCap.round,
                      );
                    },
                  ),
                ),
                const SizedBox(
                  height: 50.0,
                ),
                const Expanded(
                  child: SizedBox(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
