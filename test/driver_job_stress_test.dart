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
      final job = DriverJob.fromJson({
        'id': i + 1,
        'reference': 'AIMS-R90-$i',
        'status': completedPrefix == stopCount ? 'completed' : 'active',
        'stops': stops,
      });

      expect(job.stops.length, stopCount);
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