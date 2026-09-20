import 'dart:convert';

import 'package:aims_flow_scanner/services/driver_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('10000 international job variants select the correct current stop', () {
    const countries = [
      ('HU', 'Győr, Ipari park 1.', '+36 30 123 4567'),
      ('SK', 'Komárno, Priemyselná 12', '+421 905 123 456'),
      ('PL', 'Gliwice, ul. Portowa 7', '+48 501 234 567'),
      ('LT', 'Kaunas, Pramonės pr. 16', '+370 612 34567'),
      ('DE', 'Regensburg, Siemensstraße 9', '+49 151 23456789'),
    ];

    for (var i = 0; i < 10000; i++) {
      final stopCount = 1 + (i % 5);
      final completedPrefix = i % (stopCount + 1);
      final stops = <Map<String, dynamic>>[];

      for (var j = 0; j < stopCount; j++) {
        final country = countries[(i + j) % countries.length];
        stops.add({
          'id': (i * 10) + j + 1,
          'type': j.isEven ? 'pickup' : 'delivery',
          'order': j + 1,
          'company': 'AIMS ${country.$1} #$i-$j',
          'address': '${country.$1} · ${country.$2}',
          'phone': country.$3,
          'latitude': 47.0 + ((i + j) % 1000) / 10000,
          'longitude': 17.0 + ((i * 7 + j) % 1000) / 10000,
          'arrived': j < completedPrefix,
          'completed': j < completedPrefix,
        });
      }
      final wireStops = i.isEven
          ? stops
          : stops.reversed.toList(growable: false);
      final job = DriverJob.fromJson({
        'id': i + 1,
        'reference': 'AIMS-R90-$i',
        'status': completedPrefix == stopCount ? 'completed' : 'active',
        'stops': wireStops,
      });

      expect(job.stops.length, stopCount);
      expect(
        job.stops.map((stop) => stop.order).toList(),
        List<int>.generate(stopCount, (index) => index + 1),
        reason: 'variant $i stop order',
      );
      if (completedPrefix == stopCount) {
        expect(job.currentStop, isNull, reason: 'completed job $i');
      } else {
        expect(
          job.currentStop?.id,
          stops[completedPrefix]['id'],
          reason: 'variant $i current stop',
        );
        expect(job.currentStop?.address, isNotEmpty);
        expect(job.currentStop?.phone, startsWith('+'));
      }
    }
  });

  test('10000 international jobs survive offline cache JSON round-trip', () {
    const samples = [
      ('HU', 'Győr – Ipari park 1.', '+36 30 123 4567'),
      ('SK', 'Komárno – Bratislavská cesta 4', '+421 905 123 456'),
      ('PL', 'Łódź – Aleja Piłsudskiego 12', '+48 501 234 567'),
      ('LT', 'Šiauliai – Pramonės g. 8', '+370 612 34567'),
      ('DE', 'München – Straße der Einheit 3', '+49 151 23456789'),
    ];

    for (var i = 0; i < 10000; i++) {
      final sample = samples[i % samples.length];
      final original = DriverJob.fromJson({
        'id': i + 100000,
        'reference': 'CACHE-$i-${sample.$1}',
        'status': 'active',
        'seenAt': '2026-09-20T10:00:00Z',
        'acceptedAt': '2026-09-20T10:01:00Z',
        'stops': [
          {
            'id': i * 2 + 2,
            'type': 'delivery',
            'order': 2,
            'company': 'Cél ${sample.$1}',
            'address': sample.$2,
            'phone': sample.$3,
            'latitude': 48.123456,
            'longitude': 17.654321,
            'arrived': false,
            'completed': false,
          },
          {
            'id': i * 2 + 1,
            'type': 'pickup',
            'order': 1,
            'company': 'Felrakó – ${sample.$1}',
            'address': 'Komárom · Európa út $i',
            'phone': '+36 20 555 0000',
            'latitude': 47.743,
            'longitude': 18.121,
            'arrived': true,
            'completed': true,
          },
        ],
      });

      final decoded = jsonDecode(jsonEncode(original.toJson()));
      final restored = DriverJob.fromJson(
        Map<String, dynamic>.from(decoded as Map),
      );

      expect(restored.id, original.id);
      expect(restored.reference, original.reference);
      expect(restored.acceptedAt, original.acceptedAt);
      expect(restored.stops.map((stop) => stop.order).toList(), [1, 2]);
      expect(restored.stops[1].address, sample.$2);
      expect(restored.stops[1].phone, sample.$3);
      expect(restored.currentStop?.id, i * 2 + 2);
    }
  });

  test('10000 HTTP status variants keep transient stop failures retryable', () {
    const transient = [408, 429, 500, 502, 503, 504, 599];
    const terminal = [400, 401, 403, 404, 409, 422];

    for (var i = 0; i < 10000; i++) {
      final useTransient = i.isEven;
      final status = useTransient
          ? transient[i % transient.length]
          : terminal[i % terminal.length];
      final error = DriverApiException(status, 'HTTP $status');
      expect(
        error.retryable,
        useTransient,
        reason: 'status $status at variant $i',
      );
    }
  });

  test('10000 empty or fully completed jobs never expose a fake next stop', () {
    for (var i = 0; i < 10000; i++) {
      final empty = i.isEven;
      final job = DriverJob.fromJson({
        'id': i,
        'reference': 'DONE-$i',
        'status': 'completed',
        'stops': empty
            ? const []
            : [
                {
                  'id': i + 1,
                  'type': 'delivery',
                  'order': 1,
                  'company': 'Done',
                  'address': 'Completed stop',
                  'phone': '',
                  'latitude': 47.0,
                  'longitude': 17.0,
                  'arrived': true,
                  'completed': true,
                },
              ],
      });
      expect(job.currentStop, isNull);
    }
  });
}