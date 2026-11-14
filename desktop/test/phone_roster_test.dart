import 'package:flutter_test/flutter_test.dart';
import 'package:beamadb_desktop/core/store.dart';
import 'package:beamadb_desktop/core/adb.dart';

void main() {
  test(
    'unresponsive local transport falls back without waiting for adb offline',
    () async {
      final store = AppStore(adb: UnreachableLocalAdb());
      store.phoneRoutes.addAll({'10.0.0.2:45885': 'a', '127.0.0.1:45900': 'a'});
      store.devices = [
        const Device('10.0.0.2:45885', 'device', 'Phone'),
        const Device('127.0.0.1:45900', 'device', 'Phone'),
      ];
      store.selected = '10.0.0.2:45885';
      await store.verifyLocalRoute(store.selected!);
      expect(store.selected, '127.0.0.1:45900');
      expect(store.phones.single.preferred!.relay, isTrue);
      store.dispose();
    },
  );
  test('prefers local over relay and returns to local after recovery', () {
    final store = AppStore();
    store.phoneRoutes.addAll({
      '10.0.0.2:45885': 'a',
      '127.0.0.1:45900': 'a',
      'usb': 'a',
    });
    const local = Device('10.0.0.2:45885', 'device', 'Phone');
    const relay = Device('127.0.0.1:45900', 'device', 'Phone');
    store.devices = [relay, local];
    store.selected = relay.serial;
    store.reconcileSelection();
    expect(store.selected, local.serial);
    expect(store.phones.single.preferred!.serial, local.serial);
    store.devices = [relay];
    store.reconcileSelection();
    expect(store.selected, relay.serial);
    store.devices = [relay, local];
    store.reconcileSelection();
    expect(store.selected, local.serial);
    store.devices.add(const Device('usb', 'device', 'Phone'));
    store.reconcileSelection();
    expect(store.selected, 'usb');
    store.dispose();
  });
  test('verified relay clears stale setup failures for that phone only', () {
    final store = AppStore();
    store.phoneRoutes.addAll({
      'wifi-a': 'phone-a',
      '127.0.0.1:45901': 'phone-a',
      'usb-b': 'phone-b',
    });
    store.linkSetup.addAll({
      'wifi-a': 'Phone setup failed',
      'usb-b': 'Phone setup failed',
    });
    store.markInternetVerified('wifi-a');
    expect(store.linkSetup['wifi-a'], 'Phone setup failed');
    store.markInternetVerified('127.0.0.1:45901');
    expect(store.linkSetup['wifi-a'], 'Internet connection verified');
    expect(store.linkSetup['usb-b'], 'Phone setup failed');
    store.dispose();
  });
  test('removed phones stay hidden even when ADB reports a route', () {
    final store = AppStore();
    store.savedPhones['phone-a'] = {'model': 'Removed phone'};
    store.phoneRoutes['usb-a'] = 'phone-a';
    store.removedPhones['phone-a'] = 'Uninstall pending';
    store.devices = [const Device('usb-a', 'device', 'Removed phone')];
    expect(store.phones, isEmpty);
    store.dispose();
  });
  test(
    'cellular handover selects the working route of the same phone only',
    () {
      final store = AppStore();
      store.phoneRoutes.addAll({
        'wifi': 'phone-a',
        '127.0.0.1:45900': 'phone-a',
        'usb-b': 'phone-b',
      });
      store.selected = 'wifi';
      store.devices = [
        const Device('wifi', 'offline', 'Phone'),
        const Device('usb-b', 'device', 'Other'),
        const Device('127.0.0.1:45900', 'device', 'Phone'),
      ];
      store.reconcileSelection();
      expect(store.selected, '127.0.0.1:45900');
      store.devices = [const Device('usb-b', 'device', 'Other')];
      store.reconcileSelection();
      expect(store.selected, '127.0.0.1:45900');
      store.dispose();
    },
  );
  test('groups USB and remote connections and retains offline phones', () {
    final store = AppStore();
    store.savedPhones['phone-a'] = {'model': 'Pixel', 'battery': '73'};
    store.savedPhones['phone-b'] = {'name': 'Work phone', 'battery': '40'};
    store.phoneRoutes.addAll({
      'usb-a': 'phone-a',
      '100.64.0.1:5555': 'phone-a',
    });
    store.devices = [
      const Device('usb-a', 'device', 'Pixel'),
      const Device('100.64.0.1:5555', 'device', 'Pixel'),
    ];
    expect(store.phones.length, 2);
    expect(store.phones.first.online, isTrue);
    expect(store.phones.first.preferred!.serial, 'usb-a');
    expect(store.phones.last.online, isFalse);
    store.devices = [];
    expect(store.phones.length, 2);
    expect(store.phones.every((phone) => !phone.online), isTrue);
    expect(store.phones.first.battery, '73');
    store.dispose();
  });
}

class UnreachableLocalAdb extends Adb {
  @override
  Future<String> shell(
    String device,
    String command, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    throw const BeamException('Local network unreachable');
  }
}
