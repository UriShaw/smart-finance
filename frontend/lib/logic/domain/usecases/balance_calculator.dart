import '../entities/common.dart';
import '../entities/finance_transaction.dart';

class BalanceSummary {
  const BalanceSummary({
    required this.incomeMinor,
    required this.expenseMinor,
  });

  static const empty = BalanceSummary(incomeMinor: 0, expenseMinor: 0);

  final int incomeMinor;
  final int expenseMinor;

  int get balanceMinor => incomeMinor - expenseMinor;
}

class BalanceCalculator {
  const BalanceCalculator._();

  static BalanceSummary summarize(Iterable<LedgerEntry> entries) {
    var income = 0;
    var expense = 0;
    for (final e in entries) {
      if (e.amountMinor <= 0) continue;
      if (e.type == TxType.income) {
        income += e.amountMinor;
      } else {
        expense += e.amountMinor;
      }
    }
    return BalanceSummary(incomeMinor: income, expenseMinor: expense);
  }
}
