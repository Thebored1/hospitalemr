class Task {
  final String id;
  final String title;
  final String description;
  final String raisedBy;
  final DateTime raisedOn;
  String status; // "Open", "In Progress", "Resolved"
  final String allottedBudget;
  final DateTime fixBy;
  final String location;
  final String issueCategory;

  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.raisedBy,
    required this.raisedOn,
    required this.status,
    required this.allottedBudget,
    required this.fixBy,
    required this.location,
    required this.issueCategory,
  });

  // Helper method to get formatted date
  String get formattedRaisedOn {
    return "${raisedOn.day.toString().padLeft(2, '0')}/${raisedOn.month.toString().padLeft(2, '0')}/${raisedOn.year}";
  }

  // Helper method to get formatted time
  String get formattedRaisedTime {
    return "${raisedOn.hour.toString().padLeft(2, '0')}:${raisedOn.minute.toString().padLeft(2, '0')}";
  }

  // Helper method to get formatted fix by date
  String get formattedFixBy {
    return "${fixBy.day.toString().padLeft(2, '0')}/${fixBy.month.toString().padLeft(2, '0')}/${fixBy.year}";
  }

  // Helper method to get formatted fix by time
  String get formattedFixByTime {
    return "${fixBy.hour.toString().padLeft(2, '0')}:${fixBy.minute.toString().padLeft(2, '0')}";
  }

  // Static method to get sample tasks
  static List<Task> getSampleTasks() {
    final now = DateTime(2005, 12, 15, 16, 15);
    final fixBy = DateTime(2005, 12, 16, 16, 15);

    return [
      Task(
        id: '1',
        title: 'Broken Lights',
        description:
            'Vivamus porta ex ac tristique hendrerit. Pellentesque vitae purus elit. Vivamus non nibh ut ante convallis egestas eu ac mi. Ut gravida euismod libero eget tempor. In eu erat ut sem volutpat rhoncus eget sit Vivamus porta ex ac tristique hendrerit. Pellentesque vitae purus elit. Vivamus non nibh ut ante convallis egestas eu ac mi. Ut gravida euismod libero eget tempor.',
        raisedBy: 'Admin',
        raisedOn: now,
        status: 'In Progress',
        allottedBudget: '800/-',
        fixBy: fixBy,
        location: 'Ward A',
        issueCategory: 'Electrical',
      ),
      Task(
        id: '2',
        title: 'Broken Seats',
        description:
            'Vivamus porta ex ac tristique hendrerit. Pellentesque vitae purus elit. Vivamus non nibh ut ante convallis egestas eu ac mi. Ut gravida euismod libero eget tempor.',
        raisedBy: 'Admin',
        raisedOn: now,
        status: 'Open',
        allottedBudget: '600/-',
        fixBy: fixBy,
        location: 'Lobby',
        issueCategory: 'Furniture',
      ),
      Task(
        id: '3',
        title: 'Broken Fixtures',
        description:
            'Vivamus porta ex ac tristique hendrerit. Pellentesque vitae purus elit. Vivamus non nibh ut ante convallis egestas eu ac mi. Ut gravida euismod libero eget tempor.',
        raisedBy: 'Admin',
        raisedOn: now,
        status: 'In Progress',
        allottedBudget: '1200/-',
        fixBy: fixBy,
        location: 'Cafeteria',
        issueCategory: 'Plumbing',
      ),
    ];
  }

  // Static method to count open tickets
  static int countOpenTickets(List<Task> tasks) {
    return tasks.where((task) => task.status == 'Open').length;
  }

  // JSON serialization for REST API
  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'].toString(),
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      raisedBy: json['raised_by_details'] != null
          ? json['raised_by_details']['username']
          : 'Unknown',
      raisedOn: json['raised_on'] != null
          ? DateTime.parse(json['raised_on'])
          : DateTime.now(),
      status: json['status'] ?? 'Open',
      allottedBudget: json['allotted_budget'].toString(),
      fixBy: json['fix_by'] != null
          ? DateTime.parse(json['fix_by'])
          : DateTime.now().add(const Duration(days: 1)),
      location: json['location'] ?? '',
      issueCategory: json['issue_category'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      // 'raised_by' is handled by the backend automatically based on token
      'status': status,
      'allotted_budget': allottedBudget,
      'fix_by': fixBy.toIso8601String(),
      'location': location,
      'issue_category': issueCategory,
    };
  }
}
