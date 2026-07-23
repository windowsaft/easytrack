import 'package:easytrack/features/onboarding/onboarding_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<OnboardingService> service(Map<String, Object> initial) async {
    SharedPreferences.setMockInitialValues(initial);
    return OnboardingService(await SharedPreferences.getInstance());
  }

  test('a fresh install has not completed onboarding', () async {
    final onboarding = await service({});
    expect(onboarding.isComplete, isFalse);
  });

  test('markComplete persists across a reload', () async {
    final onboarding = await service({});
    await onboarding.markComplete();
    expect(onboarding.isComplete, isTrue);

    // A new instance reading the same store still sees it.
    final reloaded = OnboardingService(await SharedPreferences.getInstance());
    expect(reloaded.isComplete, isTrue);
  });

  test('an existing completed flag is read back as complete', () async {
    final onboarding = await service({'onboarding_complete_v1': true});
    expect(onboarding.isComplete, isTrue);
  });
}
