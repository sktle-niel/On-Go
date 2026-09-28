import 'package:flutter/material.dart';

/// What the client drives: the first thing a booking asks, because it decides
/// which problems are worth offering and tells a mechanic what to bring.
///
/// The booking carries it in the problem line ("Car · Flat tire"); the
/// service request contract has no field of its own for it yet.
enum VehicleType {
  car('Car', Icons.directions_car_rounded),
  motorcycle('Motorcycle', Icons.two_wheeler_rounded),
  tricycle('Tricycle', Icons.electric_rickshaw_rounded),
  ebike('E-bike', Icons.electric_bike_rounded),
  truck('Truck / Van', Icons.local_shipping_rounded),
  other('Other', Icons.more_horiz_rounded);

  const VehicleType(this.label, this.icon);

  /// As the client reads it on the tile and in the booking.
  final String label;

  /// The tile's glyph.
  final IconData icon;

  /// The problems worth naming for this vehicle, the commonest first and
  /// "Something else" always last, so the list is never a dead end.
  List<String> get commonProblems {
    switch (this) {
      case VehicleType.motorcycle:
      case VehicleType.tricycle:
        return const [
          "Won't start",
          'Flat tire',
          'Battery dead',
          'Engine problem',
          'Chain problem',
          'Brake problem',
          'Electrical issue',
          'Strange noise or vibration',
          'Accident or towing',
          'Something else',
        ];
      case VehicleType.ebike:
        return const [
          "Won't start",
          'Flat tire',
          'Battery or charging problem',
          'Motor problem',
          'Brake problem',
          'Electrical issue',
          'Strange noise or vibration',
          'Accident or towing',
          'Something else',
        ];
      case VehicleType.car:
      case VehicleType.truck:
      case VehicleType.other:
        return const [
          "Won't start",
          'Flat tire',
          'Battery dead',
          'Engine problem',
          'Overheating',
          'Brake problem',
          'Electrical issue',
          'Strange noise or vibration',
          'Accident or towing',
          'Something else',
        ];
    }
  }

  /// "your car", "your e-bike" — for a sentence.
  String get inSentence => this == VehicleType.other ? 'your vehicle' : 'your ${label.toLowerCase()}';
}
