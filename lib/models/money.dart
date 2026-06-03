import 'package:intl/intl.dart';

class Money {
  final int centavos;
  const Money(this.centavos);
  Money.pesos(double pesos) : centavos = (pesos * 100).round();
  static const zero = Money(0);

  double get pesos => centavos / 100;

  Money operator +(Money other) => Money(centavos + other.centavos);
  Money operator -(Money other) => Money(centavos - other.centavos);
  Money operator *(num factor) => Money((centavos * factor).round());
  Money operator /(num divisor) => Money((centavos / divisor).round());

  String get formatted {
    final f = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    return f.format(pesos);
  }

  String get compact {
    final f = NumberFormat.decimalPattern();
    return '₱${f.format(pesos.round())}';
  }

  @override
  bool operator ==(Object other) => other is Money && other.centavos == centavos;
  @override
  int get hashCode => centavos.hashCode;
}
