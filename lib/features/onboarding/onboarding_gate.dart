import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/ui/app_theme.dart';
import '../shell/home_shell.dart';
import 'onboarding_screen.dart';

/// Decides the first screen after the splash: onboarding for a fresh install,
/// the diary for everyone else.
///
/// The decision is a one-shot read ([shouldOnboardProvider]); any failure —
/// most likely the preferences plugin being unavailable — falls through to the
/// app rather than trapping the user on a setup screen they cannot leave.
class OnboardingGate extends ConsumerWidget {
  const OnboardingGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(shouldOnboardProvider)
        .when(
          data: (show) => show ? const OnboardingScreen() : const HomeShell(),
          // The splash has already run, so this resolves near-instantly; a bare
          // background avoids a flash of the wrong screen while it does.
          loading: () => const ColoredBox(color: AppColors.bg),
          error: (_, _) => const HomeShell(),
        );
  }
}
