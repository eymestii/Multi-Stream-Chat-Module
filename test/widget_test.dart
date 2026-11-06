import 'package:flutter_test/flutter_test.dart';
import 'package:streamchat_desktop/src/generated/streamchat.pbgrpc.dart' as pb;
import 'package:streamchat_desktop/src/ui/theme.dart';

void main() {
  test('muestra el nombre de las plataformas soportadas', () {
    expect(platformName(pb.Platform.PLATFORM_TWITCH), 'Twitch');
    expect(platformName(pb.Platform.PLATFORM_KICK), 'Kick');
  });
}
