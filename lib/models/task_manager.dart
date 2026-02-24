import '../models/task.dart';
import '../services/api_service.dart';

/// TaskManager - Singleton pattern for centralized task state management
/// Integrates with ApiService for REST API calls
class TaskManager {
  static final TaskManager _instance = TaskManager._internal();
  factory TaskManager() => _instance;
  TaskManager._internal();

  // final ApiService _apiService = ApiService(); // Removed as using static methods
  List<Task> _tasks = [];
  bool _isLoaded = false;

  List<Task> get tasks => _tasks;
  bool get isLoaded => _isLoaded;

  int get openTicketsCount {
    return _tasks.where((task) => task.status == 'Open').length;
  }

  /// Fetch tasks from API
  /// Call this on app startup or when refreshing data
  Future<void> fetchTasks() async {
    try {
      _tasks = await ApiService.fetchTasks();
      _isLoaded = true;
    } catch (e) {
      // Handle error - could show error dialog or retry
      print('Error fetching tasks: $e');
      // Fallback to sample data if API fails
      _tasks = Task.getSampleTasks();
      _isLoaded = true;
    }
  }

  /// Update task status both locally and on server
  Future<void> updateTaskStatus(String taskId, String newStatus) async {
    // Optimistic update - update UI immediately
    final task = _tasks.firstWhere((t) => t.id == taskId);
    final oldStatus = task.status;
    task.status = newStatus;

    try {
      // Send to server
      await ApiService.updateTaskStatus(taskId, newStatus);
    } catch (e) {
      // Rollback on error
      task.status = oldStatus;
      print('Error updating task status: $e');
      rethrow;
    }
  }

  /// Add a new task
  Future<void> addTask(Task task) async {
    try {
      final createdTask = await ApiService.createTask(task);
      if (createdTask != null) {
        _tasks.add(createdTask);
      }
    } catch (e) {
      print('Error adding task: $e');
      rethrow;
    }
  }

  /// Delete a task
  Future<void> deleteTask(String taskId) async {
    final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return;

    final removedTask = _tasks.removeAt(taskIndex);

    try {
      await ApiService.deleteTask(taskId);
    } catch (e) {
      // Rollback on error
      _tasks.insert(taskIndex, removedTask);
      print('Error deleting task: $e');
      rethrow;
    }
  }

  /// Refresh tasks from server
  Future<void> refresh() async {
    await fetchTasks();
  }

  /// Clear all tasks (for logout, etc.)
  void clear() {
    _tasks = [];
    _isLoaded = false;
  }
}
