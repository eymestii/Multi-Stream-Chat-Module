import 'package:flutter_test/flutter_test.dart';
import 'package:streamchat_desktop/src/generated/streamchat.pbgrpc.dart' as pb;
import 'package:streamchat_desktop/src/models/chat_line.dart';
import 'package:streamchat_desktop/src/services/event_mapper.dart';

pb.ChatEvent event(pb.ChatEvent_Payload payload, Object value) {
  final result = pb.ChatEvent()
    ..id = 'event-1'
    ..platform = pb.Platform.PLATFORM_TWITCH
    ..channel = (pb.Channel()
      ..platform = pb.Platform.PLATFORM_TWITCH
      ..id = '10'
      ..displayName = 'Canal');
  switch (payload) {
    case pb.ChatEvent_Payload.follow:
      result.follow = value as pb.Follow;
    case pb.ChatEvent_Payload.subscription:
      result.subscription = value as pb.Subscription;
    case pb.ChatEvent_Payload.giftSubscription:
      result.giftSubscription = value as pb.GiftSubscription;
    case pb.ChatEvent_Payload.raid:
      result.raid = value as pb.Raid;
    case pb.ChatEvent_Payload.cheer:
      result.cheer = value as pb.Cheer;
    default:
      throw ArgumentError('Payload no soportado por esta prueba');
  }
  return result;
}

pb.User user(String name) => pb.User()
  ..username = name.toLowerCase()
  ..displayName = name;

ChatLine lineOf(pb.ChatEvent source) {
  final update = mapEvent(source);
  expect(update, isA<AddLine>());
  return (update as AddLine).line;
}

void main() {
  test('conserva los fragmentos enriquecidos del mensaje', () {
    final source = pb.ChatEvent()
      ..id = 'message-1'
      ..platform = pb.Platform.PLATFORM_TWITCH
      ..channel = (pb.Channel()
        ..platform = pb.Platform.PLATFORM_TWITCH
        ..id = '10')
      ..message = (pb.ChatMessage()
        ..sender = user('Viewer')
        ..text = 'Hola Kappa'
        ..fragments.addAll([
          pb.MessageFragment()..text = 'Hola ',
          pb.MessageFragment()
            ..emote = (pb.Emote()
              ..name = 'Kappa'
              ..imageUrl = 'https://example.test/kappa.png'),
        ]));

    final line = lineOf(source);
    expect(line.fragments, hasLength(2));
    expect(line.fragments.last.emote.name, 'Kappa');
  });

  test('mapea follow sin depender de raw_json', () {
    final line = lineOf(event(
      pb.ChatEvent_Payload.follow,
      pb.Follow()..follower = user('Viewer'),
    ));
    expect(line.text, 'Viewer empezó a seguir el canal');
  });

  test('mapea detalles de suscripción, regalos, raid y cheer', () {
    final subscription = lineOf(event(
      pb.ChatEvent_Payload.subscription,
      pb.Subscription()
        ..subscriber = user('Sub')
        ..isRenewal = true
        ..cumulativeMonths = 4,
    ));
    expect(subscription.text, contains('4 meses'));

    final gifts = lineOf(event(
      pb.ChatEvent_Payload.giftSubscription,
      pb.GiftSubscription()
        ..gifter = user('Gifter')
        ..total = 3,
    ));
    expect(gifts.text, 'Gifter regaló 3 suscripciones');

    final raid = lineOf(event(
      pb.ChatEvent_Payload.raid,
      pb.Raid()
        ..fromBroadcaster = user('Raider')
        ..viewers = 42,
    ));
    expect(raid.text, contains('42 espectadores'));

    final cheer = lineOf(event(
      pb.ChatEvent_Payload.cheer,
      pb.Cheer()
        ..user = user('Cheerer')
        ..amount = 100,
    ));
    expect(cheer.text, 'Cheerer envió 100 bits');
  });
}
