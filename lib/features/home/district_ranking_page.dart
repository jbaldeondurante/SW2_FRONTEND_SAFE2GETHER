import 'package:flutter/material.dart';
import 'district_ranking_widget.dart';
import '../../core/responsive_utils.dart';

class DistrictRankingPage extends StatelessWidget {
  const DistrictRankingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final maxWidth = ResponsiveHelper.getMaxContentWidth(context);
    final padding = ResponsiveHelper.getPadding(context);
    
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FC),
      appBar: AppBar(
        title: const Text('Ranking de Seguridad'),
        backgroundColor: const Color(0xFF0E2D52),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: SingleChildScrollView(
              padding: padding,
              child: const DistrictRankingWidget(),
            ),
          ),
        ),
      ),
    );
  }
}
