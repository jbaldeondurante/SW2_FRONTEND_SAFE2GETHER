import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/responsive_utils.dart';

class AlertasPage extends StatelessWidget {
  final ApiClient api;
  const AlertasPage({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    final padding = ResponsiveHelper.getPadding(context);
    final maxWidth = ResponsiveHelper.getMaxContentWidth(context);
    
    return Scaffold(
      appBar: AppBar(title: const Text('Alertas')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: padding,
              child: const Center(child: Text('Alertas y notificaciones (TODO)')),
            ),
          ),
        ),
      ),
    );
  }
}
