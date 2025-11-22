// lib/core/responsive_utils.dart
import 'package:flutter/material.dart';

/// Breakpoints para diferentes tamaños de pantalla
class ResponsiveBreakpoints {
  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;
}

/// Clase para determinar el tipo de dispositivo
enum DeviceType { mobile, tablet, desktop }

/// Clase helper para diseño responsive
class ResponsiveHelper {
  /// Obtiene el tipo de dispositivo basado en el ancho de pantalla
  static DeviceType getDeviceType(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < ResponsiveBreakpoints.mobile) {
      return DeviceType.mobile;
    } else if (width < ResponsiveBreakpoints.tablet) {
      return DeviceType.tablet;
    } else {
      return DeviceType.desktop;
    }
  }

  /// Verifica si es móvil
  static bool isMobile(BuildContext context) {
    return getDeviceType(context) == DeviceType.mobile;
  }

  /// Verifica si es tablet
  static bool isTablet(BuildContext context) {
    return getDeviceType(context) == DeviceType.tablet;
  }

  /// Verifica si es desktop
  static bool isDesktop(BuildContext context) {
    return getDeviceType(context) == DeviceType.desktop;
  }

  /// Obtiene padding responsivo
  static EdgeInsets getPadding(BuildContext context, {double factor = 1.0}) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return EdgeInsets.all(16.0 * factor);
      case DeviceType.tablet:
        return EdgeInsets.all(24.0 * factor);
      case DeviceType.desktop:
        return EdgeInsets.all(32.0 * factor);
    }
  }

  /// Obtiene tamaño de fuente responsivo
  static double getFontSize(BuildContext context, double baseSize) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return baseSize;
      case DeviceType.tablet:
        return baseSize * 1.1;
      case DeviceType.desktop:
        return baseSize * 1.2;
    }
  }

  /// Obtiene ancho máximo para contenido
  static double getMaxContentWidth(BuildContext context) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return double.infinity;
      case DeviceType.tablet:
        return 700;
      case DeviceType.desktop:
        return 1000;
    }
  }

  /// Obtiene espaciado vertical responsivo
  static double getVerticalSpacing(BuildContext context) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return 16.0;
      case DeviceType.tablet:
        return 24.0;
      case DeviceType.desktop:
        return 32.0;
    }
  }

  /// Obtiene espaciado horizontal responsivo
  static double getHorizontalSpacing(BuildContext context) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return 16.0;
      case DeviceType.tablet:
        return 24.0;
      case DeviceType.desktop:
        return 32.0;
    }
  }

  /// Obtiene número de columnas para grid
  static int getGridColumns(BuildContext context) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.mobile:
        return 1;
      case DeviceType.tablet:
        return 2;
      case DeviceType.desktop:
        return 3;
    }
  }
}

/// Widget que renderiza diferentes layouts según el tamaño de pantalla
class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    final deviceType = ResponsiveHelper.getDeviceType(context);

    switch (deviceType) {
      case DeviceType.mobile:
        return mobile;
      case DeviceType.tablet:
        return tablet ?? mobile;
      case DeviceType.desktop:
        return desktop ?? tablet ?? mobile;
    }
  }
}

/// Widget para centrar contenido con ancho máximo
class ResponsiveContainer extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final EdgeInsets? padding;

  const ResponsiveContainer({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveMaxWidth = maxWidth ?? ResponsiveHelper.getMaxContentWidth(context);
    final effectivePadding = padding ?? ResponsiveHelper.getPadding(context);

    return Center(
      child: Container(
        width: effectiveMaxWidth,
        padding: effectivePadding,
        child: child,
      ),
    );
  }
}
