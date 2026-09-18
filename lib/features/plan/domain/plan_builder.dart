/// Deterministic schedule and equipment matching. Medical limitations are never
/// interpreted as diagnoses; they are passed to the coach for a reviewed proposal.
class PlannedSession {
  const PlannedSession({
    required this.name,
    required this.date,
    required this.exerciseIds,
    required this.sets,
  });
  final String name;
  final DateTime date;
  final List<String> exerciseIds;
  final int sets;
}

abstract final class PlanBuilder {
  static List<PlannedSession> build({
    required List<Map<String, dynamic>> library,
    required List<String> equipment,
    required List<int> days,
    required int minutes,
    required bool personalized,
    DateTime? now,
    List<String> preferredExercises = const [],
  }) {
    final today = now ?? DateTime.now();
    final weekdays = personalized ? (days.toSet().toList()..sort()) : [1, 4, 6];
    final selectedEquipment = equipment.map((e) => e.toLowerCase()).toSet();
    bool available(Map<String, dynamic> e) {
      final kind = e['equipment'].toString().toLowerCase();
      return kind == 'bodyweight' ||
          selectedEquipment.isEmpty && kind == 'dumbbell' ||
          selectedEquipment.any(
            (s) =>
                s.contains(kind) ||
                kind.contains(s) ||
                s == 'gym' && kind == 'machine',
          );
    }

    final availableExercises = library.where(available).toList();
    if (availableExercises.isEmpty) return [];
    final templates = ['Lower body', 'Upper body', 'Full body'];
    final targetCount = personalized ? (minutes ~/ 7).clamp(2, 6) : 4;
    final sets = personalized && minutes < 25 ? 2 : 3;
    return weekdays.indexed.map((entry) {
      final title = templates[entry.$1 % 3];
      var candidates = availableExercises
          .where(
            (e) => title == 'Lower body'
                ? ['legs', 'core'].contains(e['muscle_group'])
                : title == 'Upper body'
                ? e['muscle_group'] != 'legs'
                : true,
          )
          .toList();
      candidates.sort((a, b) {
        final pa = preferredExercises.any(
          (p) => a['name'].toString().toLowerCase().contains(p.toLowerCase()),
        );
        final pb = preferredExercises.any(
          (p) => b['name'].toString().toLowerCase().contains(p.toLowerCase()),
        );
        return (pa == pb)
            ? 0
            : pa
            ? -1
            : 1;
      });
      if (candidates.length < 2) candidates = availableExercises;
      final offset = (entry.$2 - today.weekday + 7) % 7;
      return PlannedSession(
        name: entry.$1 < 3 ? title : '$title · ${entry.$1 ~/ 3 + 1}',
        date: DateTime(
          today.year,
          today.month,
          today.day,
        ).add(Duration(days: offset)),
        exerciseIds: candidates
            .take(targetCount)
            .map((e) => e['id'] as String)
            .toList(),
        sets: sets,
      );
    }).toList();
  }
}
