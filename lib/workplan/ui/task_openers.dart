import 'package:flutter/material.dart';

import '../../ui/wm_sheet.dart';
import '../workplan_services.dart';
import 'my_work_controller.dart';
import 'task_sheet.dart';

/// Opens one task as a sheet — straight on [form] when given (a swipe
/// button) — then My Work is read again. The tab and Home's "Needs you" rows
/// both open tasks through this.
Future<void> openTask(
  BuildContext context,
  MyWorkController controller,
  WorkPlanServices services,
  String taskId, {
  VoidCallback? onMakeRequest,
  TaskForm? form,
}) async {
  await showWmSheet<void>(
    context,
    builder: (_) => TaskSheet(controller: controller, services: services, taskId: taskId, onMakeRequest: onMakeRequest, initialForm: form),
  );
  await controller.refresh();
}
