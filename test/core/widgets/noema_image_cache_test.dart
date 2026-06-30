import 'package:flutter_test/flutter_test.dart';
import 'package:noema/core/widgets/noema_image_cache.dart';

void main() {
  test('image cache budget scales by device memory and screen profile', () {
    expect(
      noemaImageCacheBudgetBytes(
        memoryClassMb: 256,
        totalMemoryMb: 7539,
        screenWidthPixels: 1080,
        screenHeightPixels: 2400,
      ),
      192 << 20,
    );

    expect(
      noemaImageCacheBudgetBytes(
        memoryClassMb: 128,
        totalMemoryMb: 4096,
        screenWidthPixels: 1080,
        screenHeightPixels: 2400,
      ),
      96 << 20,
    );

    expect(
      noemaImageCacheBudgetBytes(
        memoryClassMb: 128,
        totalMemoryMb: 2048,
        screenWidthPixels: 720,
        screenHeightPixels: 1600,
        isLowRamDevice: true,
      ),
      48 << 20,
    );
  });
}
