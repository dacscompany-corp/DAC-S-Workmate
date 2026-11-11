import 'package:flutter/material.dart';

import '../workplan_services.dart';
import 'my_work_controller.dart';
import 'task_screen.dart';

/// Opens one task, then My Work is read again. The tab and Home's "Needs
/// you" rows both open tasks through this.
Future<void> openTask(
  BuildContext context,
  MyWorkController controller,
  WorkPlanServices services,
  String taskId, {
  VoidCallback? onMakeRequest,
}) async {
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => TaskScreen(controller: controller, services: services, taskId: taskId, onMakeRequest: onMakeRequest),
  ));
  await controller.refresh();
}
