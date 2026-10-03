// Backend şemalarıyla eşleşen veri modelleri.

// Kategori listesi categories.dart'ta; models.dart'ı kullanan ekranlar için buradan da
// erişilebilir.
export 'categories.dart' show kCategories, kTotalBudget;

/// Uygulama sürümü (pubspec.yaml'daki version ile aynı tutulmalı).
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

class TransactionModel {
  final int id;
  final double amount;
  final String type; // income | expense
  final String category;
  final bool autoCategorized;
  final bool isRecurring;
  final String note;
  final String occurredOn; // "YYYY-MM-DD"

  /// Yalnızca ekleme ve güncelleme cevabında dolu: bu kayıtla %80'i geçen bütçeler.
  final List<BudgetAlertModel> budgetAlerts;

  TransactionModel({
    required this.id,
    required this.amount,
    required this.type,
    required this.category,
    required this.autoCategorized,
    required this.isRecurring,
    required this.note,
    required this.occurredOn,
    this.budgetAlerts = const [],
  });

  factory TransactionModel.fromJson(Map<String, dynamic> j) => TransactionModel(
        id: j['id'],
        amount: (j['amount'] as num).toDouble(),
        type: j['type'],
        category: j['category'],
        autoCategorized: j['auto_categorized'] ?? false,
        isRecurring: j['is_recurring'] ?? false,
        note: j['note'] ?? '',
        occurredOn: j['occurred_on'] ?? '',
        budgetAlerts: ((j['budget_alerts'] as List?) ?? const [])
            .map((e) => BudgetAlertModel.fromJson(e))
            .toList(),
      );
}

/// İşlem kaydedilince dönen bütçe uyarısı. Mesajda tutar yoktur; [spent] ve [limit]
/// TL cinsindendir, ekranda seçili para birimine çevrilerek gösterilir.
class BudgetAlertModel {
  final String category; // kategori adı ya da "Toplam"
  final double limit;
  final double spent;
  final double ratio; // spent / limit
  final String level; // warning | exceeded
  final bool crossed; // eşik bu kayıtla mı geçildi? (true ise daha belirgin göster)
  final String message;

  BudgetAlertModel({
    required this.category,
    required this.limit,
    required this.spent,
    required this.ratio,
    required this.level,
    required this.crossed,
    required this.message,
  });

  bool get exceeded => level == 'exceeded';

  factory BudgetAlertModel.fromJson(Map<String, dynamic> j) => BudgetAlertModel(
        category: j['category'],
        limit: (j['limit'] as num).toDouble(),
        spent: (j['spent'] as num).toDouble(),
        ratio: (j['ratio'] as num).toDouble(),
        level: j['level'],
        crossed: j['crossed'] ?? false,
        message: j['message'] ?? '',
      );
}

/// Uyarılar ekranındaki bir kayıt (backend /alerts).
class AlertModel {
  final String id; // kapatmak için ApiClient.dismissAlert(id)
  final String kind; // budget | budget_pace | anomaly | goal | recurring
  final String level; // info | warning | danger
  final String title;
  final String message;
  final String? category;

  /// TL. Anlamı türe göre: budget: bu ayki harcama, budget_pace: ay sonu tahmini,
  /// anomaly: işlem tutarı, goal: ayda ayrılması gereken (süresi geçtiyse kalan),
  /// recurring: ödeme tutarı.
  final double? amount;
  final int? refId; // ilgili işlem, hedef ya da seri
  final String? dueOn; // "YYYY-MM-DD"

  AlertModel({
    required this.id,
    required this.kind,
    required this.level,
    required this.title,
    required this.message,
    this.category,
    this.amount,
    this.refId,
    this.dueOn,
  });

  factory AlertModel.fromJson(Map<String, dynamic> j) => AlertModel(
        id: j['id'],
        kind: j['kind'],
        level: j['level'],
        title: j['title'] ?? '',
        message: j['message'] ?? '',
        category: j['category'],
        amount: (j['amount'] as num?)?.toDouble(),
        refId: j['ref_id'],
        dueOn: j['due_on'],
      );
}

/// Ay seçici için: işlem olan bir ay ve toplamları (backend /transactions/months).
class MonthSummaryModel {
  final String month; // "YYYY-MM"
  final double income;
  final double expense;
  final int count;

  MonthSummaryModel({
    required this.month,
    required this.income,
    required this.expense,
    required this.count,
  });

  factory MonthSummaryModel.fromJson(Map<String, dynamic> j) => MonthSummaryModel(
        month: j['month'],
        income: (j['income'] as num).toDouble(),
        expense: (j['expense'] as num).toDouble(),
        count: j['count'],
      );
}

/// Profil bilgileri (backend /auth/me).
class UserModel {
  final int id;
  final String email;
  final String displayName;
  final DateTime createdAt; // üyelik tarihi
  final bool alertsEnabled; // Profil > Bildirimler
  final bool aiConsent; // sohbet asistanı için veri paylaşımı onayı

  UserModel({
    required this.id,
    required this.email,
    required this.displayName,
    required this.createdAt,
    required this.alertsEnabled,
    required this.aiConsent,
  });

  factory UserModel.fromJson(Map<String, dynamic> j) => UserModel(
        id: j['id'],
        email: j['email'],
        displayName: j['display_name'] ?? '',
        createdAt: DateTime.parse(j['created_at']),
        alertsEnabled: j['alerts_enabled'] ?? true,
        aiConsent: j['ai_consent_at'] != null,
      );
}

/// Ana sayfa özeti (backend /transactions/summary). Tutarlar TL.
class SummaryModel {
  final double balance;
  final double totalIncome;
  final double totalExpense;
  final String month; // "YYYY-MM": istenen ay (varsayılan bu ay)
  final double monthIncome;
  final double monthExpense;
  final List<({String category, double total})> monthByCategory;

  SummaryModel({
    required this.balance,
    required this.totalIncome,
    required this.totalExpense,
    required this.month,
    required this.monthIncome,
    required this.monthExpense,
    required this.monthByCategory,
  });

  factory SummaryModel.fromJson(Map<String, dynamic> j) => SummaryModel(
        balance: (j['balance'] as num).toDouble(),
        totalIncome: (j['total_income'] as num).toDouble(),
        totalExpense: (j['total_expense'] as num).toDouble(),
        month: j['month'] ?? '',
        monthIncome: (j['month_income'] as num?)?.toDouble() ?? 0,
        monthExpense: (j['month_expense'] as num).toDouble(),
        monthByCategory: (j['month_by_category'] as List)
            .map((e) => (
                  category: e['category'] as String,
                  total: (e['total'] as num).toDouble()
                ))
            .toList(),
      );
}

class BudgetModel {
  final int id;
  final String category;
  final double monthlyLimit;
  final double spent;

  BudgetModel({
    required this.id,
    required this.category,
    required this.monthlyLimit,
    required this.spent,
  });

  double get ratio => monthlyLimit == 0 ? 0 : (spent / monthlyLimit);

  factory BudgetModel.fromJson(Map<String, dynamic> j) => BudgetModel(
        id: j['id'],
        category: j['category'],
        monthlyLimit: (j['monthly_limit'] as num).toDouble(),
        spent: (j['spent'] as num?)?.toDouble() ?? 0,
      );
}

class CategorySuggestion {
  final String category;
  final double confidence;
  final String model;
  CategorySuggestion(this.category, this.confidence, this.model);

  factory CategorySuggestion.fromJson(Map<String, dynamic> j) =>
      CategorySuggestion(
          j['category'], (j['confidence'] as num).toDouble(), j['model']);
}

class ForecastModel {
  final double currentMonthSpent;
  final double projectedMonthEnd;
  final double nextMonthPrediction;
  final String method; // trend | last_month | run_rate
  final String velocity; // Yüksek | Normal | Düşük
  final List<({String month, double total})> history;

  ForecastModel({
    required this.currentMonthSpent,
    required this.projectedMonthEnd,
    required this.nextMonthPrediction,
    required this.method,
    required this.velocity,
    required this.history,
  });

  factory ForecastModel.fromJson(Map<String, dynamic> j) => ForecastModel(
        currentMonthSpent: (j['current_month_spent'] as num).toDouble(),
        projectedMonthEnd: (j['projected_month_end'] as num).toDouble(),
        nextMonthPrediction: (j['next_month_prediction'] as num).toDouble(),
        method: j['method'],
        velocity: j['velocity'],
        history: (j['history'] as List)
            .map((e) => (
                  month: e['month'] as String,
                  total: (e['total'] as num).toDouble()
                ))
            .toList(),
      );
}

class GoalModel {
  final int id;
  final String title;
  final double targetAmount;
  final double currentAmount;
  final String? deadline; // "YYYY-MM-DD"
  final double progress; // 0..1
  final int? daysLeft; // son tarih yoksa null, geçtiyse negatif
  final int? monthsLeft;
  final double? monthlyNeeded; // hedefe yetişmek için ayda ayrılması gereken (TL)

  /// completed | no_deadline | on_track | behind | overdue
  /// (Tamamlandı, Son tarih yok, Yolunda, Geride, Süresi geçti)
  final String status;

  GoalModel({
    required this.id,
    required this.title,
    required this.targetAmount,
    required this.currentAmount,
    required this.deadline,
    required this.progress,
    this.daysLeft,
    this.monthsLeft,
    this.monthlyNeeded,
    this.status = 'no_deadline',
  });

  double get remaining => (targetAmount - currentAmount).clamp(0, targetAmount);

  factory GoalModel.fromJson(Map<String, dynamic> j) => GoalModel(
        id: j['id'],
        title: j['title'],
        targetAmount: (j['target_amount'] as num).toDouble(),
        currentAmount: (j['current_amount'] as num).toDouble(),
        deadline: j['deadline'],
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        daysLeft: j['days_left'],
        monthsLeft: j['months_left'],
        monthlyNeeded: (j['monthly_needed'] as num?)?.toDouble(),
        status: j['status'] ?? 'no_deadline',
      );
}

class InsightModel {
  final String icon;
  final String tone; // good | warn | neutral
  final String title;
  final String text;

  InsightModel({
    required this.icon,
    required this.tone,
    required this.title,
    required this.text,
  });

  factory InsightModel.fromJson(Map<String, dynamic> j) => InsightModel(
        icon: j['icon'] ?? 'info',
        tone: j['tone'] ?? 'neutral',
        title: j['title'] ?? '',
        text: j['text'] ?? '',
      );
}

class AnomalyModel {
  final double amount;
  final String category;
  final String note;
  final String occurredOn;
  final String severity; // high | medium
  final String reason;

  AnomalyModel({
    required this.amount,
    required this.category,
    required this.note,
    required this.occurredOn,
    required this.severity,
    required this.reason,
  });

  factory AnomalyModel.fromJson(Map<String, dynamic> j) => AnomalyModel(
        amount: (j['amount'] as num).toDouble(),
        category: j['category'],
        note: j['note'] ?? '',
        occurredOn: j['occurred_on'] ?? '',
        severity: j['severity'] ?? 'medium',
        reason: j['reason'] ?? '',
      );
}
